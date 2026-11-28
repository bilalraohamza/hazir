import 'llm_client.dart';

String llmErrorText(LlmErrorKind kind) => switch (kind) {
  LlmErrorKind.noApiKey => 'Set up the AI assistant in Settings to use chat.',
  LlmErrorKind.unauthorized =>
    'Your API key was rejected. Check it in Settings.',
  LlmErrorKind.rateLimited => 'The AI service is busy. Try again in a moment.',
  LlmErrorKind.quotaExceeded =>
    "Your AI account has run out of free quota. Check your provider's console.",
  LlmErrorKind.network || LlmErrorKind.timeout =>
    "Couldn't reach the AI service. Check your internet connection.",
  LlmErrorKind.server || LlmErrorKind.badResponse =>
    'The AI service had a problem. Try again or add it manually.',
};
