sealed class LlmMessage {
  const LlmMessage();
}

class SystemMessage extends LlmMessage {
  const SystemMessage(this.text);
  final String text;
}

class UserMessage extends LlmMessage {
  const UserMessage(this.text);
  final String text;
}

class AssistantMessage extends LlmMessage {
  const AssistantMessage(this.text, this.toolCalls);
  final String? text;
  final List<ToolCall> toolCalls;
}

class ToolMessage extends LlmMessage {
  const ToolMessage(this.toolCallId, this.name, this.jsonContent);
  final String toolCallId;
  final String name;
  final String jsonContent;
}

class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    required this.rawArguments,
  });
  final String id;
  final String name;
  final Map<String, Object?> arguments;
  final String rawArguments;
}

class LlmResponse {
  const LlmResponse({required this.text, required this.toolCalls});
  final String? text;
  final List<ToolCall> toolCalls;
}

abstract class LlmClient {
  Future<LlmResponse> complete({
    required List<LlmMessage> messages,
    required List<Map<String, Object?>> tools,
  });
}

enum LlmErrorKind {
  noApiKey,
  unauthorized,
  rateLimited,
  quotaExceeded,
  timeout,
  network,
  badResponse,
  server,
}

class LlmException implements Exception {
  const LlmException(this.kind, this.message);
  final LlmErrorKind kind;
  final String message;

  @override
  String toString() => message;
}
