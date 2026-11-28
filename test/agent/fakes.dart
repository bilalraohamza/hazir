import 'dart:async';

import 'package:budget_app/features/agent/llm/llm_client.dart';

class FakeLlmClient implements LlmClient {
  FakeLlmClient(this.responses);

  final List<FutureOr<LlmResponse> Function()> responses;
  final requests =
      <({List<LlmMessage> messages, List<Map<String, Object?>> tools})>[];

  @override
  Future<LlmResponse> complete({
    required List<LlmMessage> messages,
    required List<Map<String, Object?>> tools,
  }) async {
    requests.add((messages: List.of(messages), tools: List.of(tools)));
    return responses[requests.length - 1]();
  }
}
