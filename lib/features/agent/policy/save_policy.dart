import '../../../core/money/money.dart';
import '../tools/tool_spec.dart';

enum Decision { autoSave, propose }

class SavePolicy {
  Decision decide({
    required String toolName,
    required ToolKind kind,
    required Map<String, Object?> preview,
    required Money threshold,
  }) {
    if (kind != ToolKind.write ||
        (toolName != 'add_expense' && toolName != 'add_income') ||
        threshold.minor <= 0) {
      return Decision.propose;
    }

    final assumed = preview['assumed'];
    if (assumed is! List || assumed.isNotEmpty) return Decision.propose;

    return switch (preview['policy_amount']) {
      {'minor': int minor, 'currency': String currency}
          when currency == threshold.currency &&
              minor >= 0 &&
              minor < threshold.minor =>
        Decision.autoSave,
      _ => Decision.propose,
    };
  }
}
