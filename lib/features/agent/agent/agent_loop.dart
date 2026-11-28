import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../ledger/deletion_service.dart';
import '../chat/chat_repository.dart';
import '../llm/llm_client.dart';
import '../policy/save_policy.dart';
import '../settings/agent_settings.dart';
import '../tools/tool_registry.dart';
import '../tools/tool_spec.dart';
import '../tools/write_tool.dart' show sameJsonValue;
import 'context_builder.dart';
import 'system_prompt.dart';

const _newEntryTools = {'add_expense', 'add_income', 'add_transfer'};
const _completed = {'saved', 'confirmed'};

class AgentLoop {
  AgentLoop(
    this._llm,
    this._tools,
    this._policy,
    this._chat,
    this._context,
    this._settings,
    this._deletion,
  );

  final LlmClient _llm;
  final ToolRegistry _tools;
  final SavePolicy _policy;
  final ChatRepository _chat;
  final AgentContextBuilder _context;
  final AgentSettingsRepository _settings;
  final DeletionService _deletion;
  final _busy = ValueNotifier(false);

  ValueListenable<bool> get busy => _busy;

  Future<void> send(String userText) async {
    if (userText.trim().isEmpty) return;
    await _whileIdle(() async {
      final turnId = await _chat.addUser(userText);
      await _run(await _chat.userMessage(turnId));
    });
  }

  Future<void> retry(int turnId) => _whileIdle(() async {
    final turns = await _chat.watchTurns(limit: 1).first;
    if (turns.isEmpty || turns.single.user.id != turnId) return;
    final turn = turns.single;
    final newest = turn.actions.lastOrNull;
    if (newest == null || newest.kind != 'error' || newest.status != 'failed') {
      return;
    }
    await _chat.setActionStatus(newest.id, 'cancelled');
    await _run(turn.user, retrying: true);
  });

  Future<void> _whileIdle(Future<void> Function() work) async {
    if (_busy.value) return;
    _busy.value = true;
    try {
      await work();
    } catch (_) {
      // A storage failure can also prevent recording the error in chat.
    } finally {
      _busy.value = false;
    }
  }

  Future<void> _run(ChatMessage user, {bool retrying = false}) async {
    try {
      final messages = await _requestMessages(user, retrying: retrying);
      final schemas = _tools.schemas();
      (String, String)? lastFailedCall;
      for (var round = 0; round < 6; round++) {
        final response = await _llm.complete(
          messages: messages,
          tools: schemas,
        );
        if (response.toolCalls.isEmpty) {
          final text = response.text;
          if (text == null || text.trim().isEmpty) {
            await _recordError(user.id, LlmErrorKind.badResponse.name);
          } else {
            await _chat.addAssistant(user.id, text);
          }
          return;
        }

        messages.add(AssistantMessage(response.text, response.toolCalls));
        for (final call in response.toolCalls) {
          final result = await _runTool(user, call);
          messages.add(
            ToolMessage(call.id, call.name, jsonEncode(result.toJson())),
          );
          if (result is ToolError) {
            final failedCall = (call.name, call.rawArguments);
            if (failedCall == lastFailedCall) {
              await _recordToolFailure(user.id);
              return;
            }
            lastFailedCall = failedCall;
          } else {
            lastFailedCall = null;
          }
        }
      }
      await _recordToolFailure(user.id);
    } on LlmException catch (error) {
      await _recordError(user.id, error.kind.name);
    } catch (_) {
      await _recordError(user.id, LlmErrorKind.badResponse.name);
    }
  }

  Future<List<LlmMessage>> _requestMessages(
    ChatMessage user, {
    required bool retrying,
  }) async {
    final messages = <LlmMessage>[
      SystemMessage(systemPrompt(await _context.build())),
    ];
    final history = await _chat.historyBefore(user.id, 8);
    final actionLinesByTurn = <int, List<String>>{};
    for (final message in history) {
      if (message.role == 'user') {
        messages.add(UserMessage(message.text));
        continue;
      }
      final turnId = message.turnId!;
      final actionLines = actionLinesByTurn[turnId] ??= _savedLines(
        await _chat.actionsForTurn(turnId),
      );
      messages.add(
        AssistantMessage([message.text, ...actionLines].join('\n'), const []),
      );
    }
    if (retrying) {
      final actionLines = _savedLines(await _chat.actionsForTurn(user.id));
      messages.add(
        SystemMessage(
          'Already done in this turn, do not repeat: ${actionLines.join('\n')}',
        ),
      );
    }
    messages.add(UserMessage(user.text));
    return messages;
  }

  List<String> _savedLines(List<ChatAction> actions) => [
    for (final action in actions)
      if (_completed.contains(action.status))
        '[saved: ${_savedSummary(action)}'
            '${action.transactionId == null ? '' : ', entry ${action.transactionId}'}]',
  ];

  String _savedSummary(ChatAction action) =>
      (_storedMap(action.argumentsJson)['summary'] as String?) ??
      action.toolName ??
      'Completed action';

  Future<ToolResult> _runTool(ChatMessage user, ToolCall call) async {
    final tool = _tools.byName(call.name);
    if (tool == null) {
      return const ToolError(
        'unknown_tool',
        'Use a tool from the supplied list.',
      );
    }
    final raw = call.rawArguments.trim();
    if (call.arguments.isEmpty &&
        raw.isNotEmpty &&
        raw != '{}' &&
        raw != 'null') {
      return const ToolError(
        'invalid_arguments',
        'Send arguments as a JSON object.',
      );
    }
    if (tool.kind == ToolKind.read) return tool.run!(call.arguments);

    final args = {...call.arguments};
    if (_newEntryTools.contains(tool.name)) {
      // Keep the default date stable when the same turn is retried.
      args['at'] ??= user.createdAt.toLocal().toIso8601String();
    }
    return _chat.transaction(() async {
      final validation = await tool.validate!(args);
      if (validation is ToolError) return validation;
      final preview = (validation as ToolOk).data;
      final previous = await _findDuplicate(user.id, tool.name, preview);
      if (previous != null) return previous;

      final decision = _policy.decide(
        toolName: tool.name,
        kind: tool.kind,
        preview: preview,
        threshold: await _settings.readLargeAmountThreshold(),
      );
      if (decision == Decision.propose) {
        await _propose(user.id, tool.name, preview);
        return _pendingResult(preview);
      }

      final result = await tool.execute!(preview);
      if (result is ToolOk) {
        await _chat.addAction(
          turnId: user.id,
          kind: 'saved',
          status: 'saved',
          toolName: tool.name,
          argumentsJson: jsonEncode(preview),
          transactionId: _transactionId(result),
          resultJson: jsonEncode(result.toJson()),
        );
      }
      return result;
    });
  }

  Future<ToolOk?> _findDuplicate(
    int turnId,
    String name,
    Map<String, Object?> preview,
  ) async {
    for (final action in await _chat.actionsForTurn(turnId)) {
      if (action.toolName != name ||
          (action.status != 'pending' && !_completed.contains(action.status))) {
        continue;
      }
      final stored = _storedMap(action.argumentsJson);
      if (!sameJsonValue(stored['arguments'], preview['arguments'])) continue;
      return action.status == 'pending'
          ? _pendingResult(stored)
          : ToolOk(_storedMap(action.resultJson));
    }
    return null;
  }

  Future<int> _propose(int turnId, String name, Map<String, Object?> preview) =>
      _chat.addAction(
        turnId: turnId,
        kind: 'proposed',
        status: 'pending',
        toolName: name,
        argumentsJson: jsonEncode(preview),
      );

  ToolOk _pendingResult(Map<String, Object?> preview) => ToolOk({
    'status': 'waiting_for_confirmation',
    'summary': preview['summary'],
  });

  Future<int> _recordError(int turnId, String kind) => _chat.addAction(
    turnId: turnId,
    kind: 'error',
    status: 'failed',
    resultJson: jsonEncode({'kind': kind}),
  );

  Future<void> _recordToolFailure(int turnId) => _chat.transaction(() async {
    await _chat.addAssistant(
      turnId,
      "I couldn't do that. You can add it manually.",
    );
    await _recordError(turnId, 'tool_failed');
  });

  Future<void> confirm(int actionId) => _whileIdle(() async {
    await _chat.transaction(() async {
      final action = await _chat.action(actionId);
      if (action == null || action.status != 'pending') return;
      final tool = _tools.byName(action.toolName ?? '');
      if (tool == null || tool.kind == ToolKind.read) {
        await _failConfirmation(
          actionId,
          const ToolError(
            'unknown_tool',
            'This action is no longer available.',
          ),
        );
        return;
      }
      final preview = _storedMap(action.argumentsJson);
      final result = await tool.execute!(preview);
      if (result is ToolOk) {
        await _chat.setActionStatus(
          actionId,
          'confirmed',
          transactionId: _transactionId(result),
          resultJson: jsonEncode(result.toJson()),
        );
        return;
      }
      final error = result as ToolError;
      if (error.code != 'changed') {
        await _failConfirmation(actionId, error);
        return;
      }
      final args = preview['arguments'];
      final fresh = args is Map<String, Object?>
          ? await tool.validate!(args)
          : const ToolError(
              'invalid_arguments',
              'The action arguments are unavailable.',
            );
      if (fresh is ToolOk) {
        await _chat.setActionStatus(
          actionId,
          'failed',
          resultJson: jsonEncode({'reason': 'changed'}),
        );
        await _propose(action.turnId, tool.name, fresh.data);
      } else {
        await _failConfirmation(
          actionId,
          fresh as ToolError,
          reason: 'changed',
        );
      }
    });
  });

  Future<void> _failConfirmation(
    int actionId,
    ToolError error, {
    String? reason,
  }) => _chat.setActionStatus(
    actionId,
    'failed',
    resultJson: jsonEncode({
      'reason': ?reason,
      'code': error.code,
      'message': error.message,
    }),
  );

  Future<void> cancel(int actionId) => _whileIdle(() async {
    await _chat.transaction(() async {
      final action = await _chat.action(actionId);
      if (action?.status == 'pending') {
        await _chat.setActionStatus(actionId, 'cancelled');
      }
    });
  });

  Future<bool> undo(int actionId) async {
    var undone = false;
    await _whileIdle(() async {
      undone = await _chat.transaction(() async {
        final action = await _chat.action(actionId);
        final entry = action?.transactionId;
        if (action == null ||
            entry == null ||
            !_completed.contains(action.status) ||
            !_newEntryTools.contains(action.toolName)) {
          return false;
        }
        await _deletion.deleteTransaction(entry);
        await _chat.setActionStatus(actionId, 'undone');
        return true;
      });
    });
    return undone;
  }
}

Map<String, Object?> _storedMap(String? json) =>
    json == null ? const {} : jsonDecode(json) as Map<String, Object?>;

int? _transactionId(ToolOk result) => switch (result.data['transaction_id']) {
  final int id => id,
  _ => null,
};
