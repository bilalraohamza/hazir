import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/agent_settings.dart';
import 'llm_client.dart';
import 'llm_errors.dart';

final llmClientProvider = Provider<LlmClient>((ref) {
  final dio = Dio();
  ref.onDispose(() => dio.close(force: true));
  return OpenAiCompatibleClient(
    ref.watch(agentSettingsRepositoryProvider),
    dio,
  );
});

// https://docs.bigmodel.cn/cn/guide/capabilities/thinking-mode
// https://docs.bigmodel.cn/cn/guide/capabilities/thinking
Map<String, Object?>? thinkingField(AgentProvider provider, String model) {
  const supported = {
    'glm-4.5',
    'glm-4.5-air',
    'glm-4.5-airx',
    'glm-4.5-flash',
    'glm-4.6',
    'glm-4.7',
    'glm-4.7-flash',
    'glm-4.7-flashx',
    'glm-5',
    'glm-5-turbo',
    'glm-5v-turbo',
    'glm-5.1',
    'glm-5.2',
  };
  return provider == AgentProvider.zhipu &&
          supported.contains(model.toLowerCase())
      ? const {'type': 'disabled'}
      : null;
}

class OpenAiCompatibleClient implements LlmClient {
  OpenAiCompatibleClient(this._repository, this._dio);

  final AgentSettingsRepository _repository;
  final Dio _dio;

  @override
  Future<LlmResponse> complete({
    required List<LlmMessage> messages,
    required List<Map<String, Object?>> tools,
  }) async {
    final ({AgentSettings settings, String? key}) connection;
    try {
      connection = await _repository.readConnection();
    } on Object {
      throw _error(LlmErrorKind.noApiKey);
    }
    final (settings: settings, key: savedKey) = connection;
    final key = savedKey?.trim() ?? '';
    final model = settings.model.trim();
    final base = Uri.tryParse(settings.baseUrl.trim());
    if (key.isEmpty ||
        model.isEmpty ||
        base == null ||
        base.scheme != 'https' ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty) {
      throw _error(LlmErrorKind.noApiKey);
    }
    final endpoint = base.removeFragment().replace(
      path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/chat/completions',
    );
    final thinking = thinkingField(settings.provider, model);
    final Response<String> response;
    try {
      response = await _dio.postUri<String>(
        endpoint,
        data: {
          'model': model,
          'messages': messages.map(_serializeMessage).toList(),
          if (tools.isNotEmpty) ...{
            'tools': [
              for (final tool in tools)
                if (tool['type'] == 'function' && tool['function'] is Map)
                  tool
                else
                  {'type': 'function', 'function': tool},
            ],
            'tool_choice': 'auto',
          },
          'temperature': 0.2,
          'thinking': ?thinking,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $key'},
          contentType: Headers.jsonContentType,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 45),
          followRedirects: false,
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (error) {
      final kind = switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => LlmErrorKind.timeout,
        DioExceptionType.connectionError ||
        DioExceptionType.badCertificate ||
        DioExceptionType.cancel => LlmErrorKind.network,
        DioExceptionType.unknown when error.error is SocketException =>
          LlmErrorKind.network,
        DioExceptionType.badResponse => _httpError(
          error.response?.statusCode,
          error.response?.data,
          settings.provider,
        ),
        _ => LlmErrorKind.badResponse,
      };
      throw _error(kind);
    } on Object {
      throw _error(LlmErrorKind.badResponse);
    }
    final body = _decode(response.data);
    final status = response.statusCode;
    final hasProviderError = body is Map && body['error'] is Map;
    if (status == null || status < 200 || status >= 300 || hasProviderError) {
      throw _error(_httpError(status, body, settings.provider));
    }
    return _parseReply(body);
  }
}

LlmException _error(LlmErrorKind kind) =>
    LlmException(kind, llmErrorText(kind));

Object? _decode(Object? value) {
  if (value is! String) return value;
  try {
    return jsonDecode(value);
  } on FormatException {
    return null;
  }
}

LlmErrorKind _httpError(int? status, Object? body, AgentProvider provider) {
  if (status != null && status >= 300 && status < 400) {
    return LlmErrorKind.badResponse;
  }
  if (status == 402) return LlmErrorKind.quotaExceeded;
  // https://docs.bigmodel.cn/cn/api/api-code
  const quotaCodes = {
    '1113',
    '1308',
    '1310',
    '1316',
    '1317',
    '1318',
    '1319',
    '1320',
    '1321',
  };
  if (provider == AgentProvider.zhipu) {
    if (_decode(body) case {'error': {'code': final Object code}}
        when quotaCodes.contains(code.toString())) {
      return LlmErrorKind.quotaExceeded;
    }
  }
  return switch (status ?? 0) {
    401 => LlmErrorKind.unauthorized,
    429 => LlmErrorKind.rateLimited,
    >= 500 && <= 599 => LlmErrorKind.server,
    _ => LlmErrorKind.badResponse,
  };
}

Map<String, Object?> _serializeMessage(LlmMessage message) => switch (message) {
  SystemMessage(:final text) => {'role': 'system', 'content': text},
  UserMessage(:final text) => {'role': 'user', 'content': text},
  AssistantMessage(:final text, :final toolCalls) => {
    'role': 'assistant',
    'content': text,
    if (toolCalls.isNotEmpty)
      'tool_calls': [
        for (final call in toolCalls)
          {
            'id': call.id,
            'type': 'function',
            'function': {'name': call.name, 'arguments': call.rawArguments},
          },
      ],
  },
  ToolMessage(:final toolCallId, :final name, :final jsonContent) => {
    'role': 'tool',
    'tool_call_id': toolCallId,
    'name': name,
    'content': jsonContent,
  },
};

LlmResponse _parseReply(Object? body) {
  if (body case {'choices': [{'message': final Map message}, ...]}) {
    final content = message['content'];
    final text = content is String && content.trim().isNotEmpty
        ? content
        : null;
    final calls = <ToolCall>[];
    final toolCalls = message['tool_calls'];
    if (toolCalls != null && toolCalls is! List) {
      throw _error(LlmErrorKind.badResponse);
    }
    if (toolCalls is List) {
      for (final call in toolCalls) {
        if (call
            case {
              'id': final String id,
              'function': {
                'name': final String name,
                'arguments': final String raw,
              },
            }
            when id.isNotEmpty && name.isNotEmpty) {
          final decoded = _decode(raw);
          calls.add(
            ToolCall(
              id: id,
              name: name,
              rawArguments: raw,
              arguments: decoded is Map<String, Object?> ? decoded : const {},
            ),
          );
        } else {
          throw _error(LlmErrorKind.badResponse);
        }
      }
    }
    if (text != null || calls.isNotEmpty) {
      return LlmResponse(text: text, toolCalls: calls);
    }
  }
  throw _error(LlmErrorKind.badResponse);
}
