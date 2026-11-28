import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:budget_app/data/db/app_database.dart';
import 'package:budget_app/features/agent/llm/llm_client.dart';
import 'package:budget_app/features/agent/llm/openai_compatible_client.dart';
import 'package:budget_app/features/agent/settings/agent_settings.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../settings/fake_agent_key_store.dart';

const key = 'fake-test-key-private';
const prompt = 'private mock prompt';
const textReply = {
  'choices': [
    {
      'message': {'content': 'OK'},
    },
  ],
};

class MockAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Object? body = textReply;
  int status = 200;
  DioExceptionType? failure;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (failure case final type?) {
      throw DioException(
        requestOptions: options,
        type: type,
        message: 'Authorization: Bearer $key $prompt',
        error: type == DioExceptionType.unknown
            ? const SocketException('offline')
            : null,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        if (status == 302) 'location': ['https://elsewhere.invalid/'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late AppDatabase db;
  late AgentSettingsRepository settings;
  late MockAdapter adapter;
  late LlmClient client;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    settings = AgentSettingsRepository(db, FakeAgentKeyStore());
    await settings.setApiKey(AgentProvider.zhipu, key);
    adapter = MockAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    client = OpenAiCompatibleClient(settings, dio);
  });

  Future<LlmResponse> complete() =>
      client.complete(messages: const [UserMessage(prompt)], tools: []);

  Matcher throwsKind(LlmErrorKind kind) => throwsA(
    isA<LlmException>()
        .having((e) => e.kind, 'kind', kind)
        .having(
          (e) => '${e.message} ${e.toString()}',
          'safe text',
          allOf(
            isNot(contains(key)),
            isNot(contains('Authorization')),
            isNot(contains(prompt)),
          ),
        ),
  );

  test('serializes messages and function schemas with saved credentials and safe options', () async {
    const tool = ToolCall(
      id: 'id',
      name: 'lookup',
      arguments: {},
      rawArguments: '{}',
    );
    final reply = await client.complete(
      messages: const [
        SystemMessage('rules'),
        UserMessage(prompt),
        AssistantMessage(null, [tool]),
        ToolMessage('id', 'lookup', '{"done":true}'),
      ],
      tools: [
        {
          'name': 'lookup',
          'parameters': {'type': 'object'},
        },
      ],
    );
    expect(reply.text, 'OK');
    expect(reply.toolCalls, isEmpty);
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(
      request.uri.toString(),
      'https://open.bigmodel.cn/api/paas/v4/chat/completions',
    );
    expect(request.headers['Authorization'], 'Bearer $key');
    expect(request.connectTimeout, const Duration(seconds: 10));
    expect(request.receiveTimeout, const Duration(seconds: 45));
    expect(request.followRedirects, isFalse);
    expect(request.data, {
      'model': 'glm-4.7-flash',
      'temperature': 0.2,
      'thinking': {'type': 'disabled'},
      'tool_choice': 'auto',
      'tools': [
        {
          'type': 'function',
          'function': {
            'name': 'lookup',
            'parameters': {'type': 'object'},
          },
        },
      ],
      'messages': [
        {'role': 'system', 'content': 'rules'},
        {'role': 'user', 'content': prompt},
        {
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {
              'id': 'id',
              'type': 'function',
              'function': {'name': 'lookup', 'arguments': '{}'},
            },
          ],
        },
        {
          'role': 'tool',
          'tool_call_id': 'id',
          'name': 'lookup',
          'content': '{"done":true}',
        },
      ],
    });
  });

  test(
    'parses multiple tool calls and preserves malformed argument strings',
    () async {
      adapter.body = {
        'choices': [
          {
            'message': {
              'content': null,
              'tool_calls': [
                {
                  'id': 'a',
                  'function': {
                    'name': 'first',
                    'arguments': '{"amount":"28.00"}',
                  },
                },
                {
                  'id': 'b',
                  'function': {'name': 'second', 'arguments': '{ broken'},
                },
                {
                  'id': 'c',
                  'function': {'name': 'third', 'arguments': '[]'},
                },
              ],
            },
          },
        ],
      };
      final reply = await complete();
      expect(reply.text, isNull);
      expect(reply.toolCalls.map((call) => (call.id, call.name)), [
        ('a', 'first'),
        ('b', 'second'),
        ('c', 'third'),
      ]);
      expect(reply.toolCalls.first.arguments, {'amount': '28.00'});
      expect(reply.toolCalls[1].arguments, isEmpty);
      expect(reply.toolCalls[1].rawArguments, '{ broken');
      expect(reply.toolCalls[2].arguments, isEmpty);
    },
  );

  test(
    'text-only requests omit tool fields and empty responses fail',
    () async {
      await complete();
      expect(adapter.requests.single.data, isNot(contains('tools')));
      expect(adapter.requests.single.data, isNot(contains('tool_choice')));
      adapter.body = {
        'choices': [
          {
            'message': {'content': '  ', 'tool_calls': []},
          },
        ],
      };
      await expectLater(complete(), throwsKind(LlmErrorKind.badResponse));
    },
  );

  for (final (status, kind) in [
    (401, LlmErrorKind.unauthorized),
    (402, LlmErrorKind.quotaExceeded),
    (429, LlmErrorKind.rateLimited),
    (500, LlmErrorKind.server),
    (302, LlmErrorKind.badResponse),
  ]) {
    test(
      'HTTP $status maps to ${kind.name} without leaking or redirecting',
      () async {
        adapter.status = status;
        adapter.body = {
          'error': {'message': 'Authorization: Bearer $key $prompt'},
        };
        await expectLater(complete(), throwsKind(kind));
        expect(adapter.requests.single.followRedirects, isFalse);
      },
    );
  }

  for (final code in [
    1113,
    '1308',
    '1310',
    '1316',
    '1317',
    '1318',
    '1319',
    '1320',
    '1321',
  ]) {
    test('Zhipu code $code maps to quotaExceeded before HTTP 429', () async {
      adapter.status = 429;
      adapter.body = {
        'error': {'code': code, 'message': key},
      };
      await expectLater(complete(), throwsKind(LlmErrorKind.quotaExceeded));
    });
  }

  for (final type in [
    DioExceptionType.connectionTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.unknown,
  ]) {
    test('transport failure ${type.name} is sanitized', () async {
      adapter.failure = type;
      await expectLater(
        complete(),
        throwsKind(
          type == DioExceptionType.unknown
              ? LlmErrorKind.network
              : LlmErrorKind.timeout,
        ),
      );
    });
  }

  for (final missing in ['key', 'model', 'URL']) {
    test('missing $missing causes no request', () async {
      if (missing == 'key') {
        await settings.clearApiKey(AgentProvider.zhipu);
      } else {
        await settings.selectProvider(AgentProvider.custom);
        await settings.setApiKey(AgentProvider.custom, key);
        if (missing == 'model') {
          await settings.saveCustomBaseUrl('https://example.invalid/v1');
        } else {
          final current = await settings.watch().first;
          await settings.save(current.copyWith(model: 'custom-model'));
        }
      }
      await expectLater(complete(), throwsKind(LlmErrorKind.noApiKey));
      expect(adapter.requests, isEmpty);
    });
  }

  test('thinking is sent only for supported Zhipu models', () {
    expect(thinkingField(AgentProvider.zhipu, 'glm-4.7-flash'), {
      'type': 'disabled',
    });
    expect(thinkingField(AgentProvider.zhipu, 'glm-5.2'), {'type': 'disabled'});
    expect(thinkingField(AgentProvider.zhipu, 'glm-5.3-flash'), isNull);
    expect(thinkingField(AgentProvider.zhipu, 'unknown'), isNull);
    expect(thinkingField(AgentProvider.openRouter, 'glm-4.7-flash'), isNull);
  });
}
