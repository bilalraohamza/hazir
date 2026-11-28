import 'package:budget_app/core/money/money.dart';
import 'package:budget_app/features/agent/policy/save_policy.dart';
import 'package:budget_app/features/agent/tools/tool_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final policy = SavePolicy();
  const cnyThreshold = Money(50000, 'CNY');
  const pkrThreshold = Money(100000, 'PKR');

  Map<String, Object?> preview(
    Object? minor, {
    String currency = 'CNY',
    Object? assumed = const <String>[],
  }) => {
    'assumed': assumed,
    'policy_amount': {'minor': minor, 'currency': currency},
  };

  for (final (name, tool, kind, data, threshold, expected) in [
    (
      'small clear expense auto-saves',
      'add_expense',
      ToolKind.write,
      preview(2800),
      cnyThreshold,
      Decision.autoSave,
    ),
    (
      '499.99 CNY auto-saves',
      'add_expense',
      ToolKind.write,
      preview(49999),
      cnyThreshold,
      Decision.autoSave,
    ),
    (
      '500.00 CNY requires confirmation',
      'add_expense',
      ToolKind.write,
      preview(50000),
      cnyThreshold,
      Decision.propose,
    ),
    (
      'PKR expense equivalent above the CNY threshold requires confirmation',
      'add_expense',
      ToolKind.write,
      {
        ...preview(50001),
        'amount': {'minor': 2000040, 'currency': 'PKR'},
      },
      cnyThreshold,
      Decision.propose,
    ),
    (
      'PKR expense without a rate requires confirmation',
      'add_expense',
      ToolKind.write,
      {
        'assumed': <String>[],
        'policy_amount': null,
        'amount': {'minor': 10000, 'currency': 'PKR'},
      },
      cnyThreshold,
      Decision.propose,
    ),
    (
      'an assumed field requires confirmation',
      'add_expense',
      ToolKind.write,
      preview(2800, assumed: ['account_id']),
      cnyThreshold,
      Decision.propose,
    ),
    for (final minor in [2800, 50000])
      (
        'transfer with policy amount $minor requires confirmation',
        'add_transfer',
        ToolKind.write,
        preview(minor),
        cnyThreshold,
        Decision.propose,
      ),
    for (final tool in [
      'edit_entry',
      'create_account',
      'rename_account',
      'archive_account',
      'create_category',
      'rename_category',
      'archive_category',
      'set_main_currency',
      'set_large_amount_threshold',
      'unknown_tool',
    ])
      (
        '$tool requires confirmation',
        tool,
        ToolKind.write,
        preview(2800),
        cnyThreshold,
        Decision.propose,
      ),
    for (final tool in [
      'delete_entry',
      'delete_account',
      'delete_category',
      'add_expense',
    ])
      (
        'destructive $tool requires confirmation',
        tool,
        ToolKind.destructive,
        preview(2800),
        cnyThreshold,
        Decision.propose,
      ),
    (
      'an eligible name with read kind requires confirmation',
      'add_income',
      ToolKind.read,
      preview(2800),
      cnyThreshold,
      Decision.propose,
    ),
    (
      'clear income below the threshold auto-saves',
      'add_income',
      ToolKind.write,
      preview(2800),
      cnyThreshold,
      Decision.autoSave,
    ),
    (
      'zero threshold requires confirmation even when the conversion rounds to zero',
      'add_expense',
      ToolKind.write,
      preview(0),
      const Money(0, 'CNY'),
      Decision.propose,
    ),
    (
      'a zero converted amount can auto-save with a positive threshold',
      'add_expense',
      ToolKind.write,
      preview(0),
      cnyThreshold,
      Decision.autoSave,
    ),
    (
      'wrong policy currency requires confirmation',
      'add_expense',
      ToolKind.write,
      preview(2800, currency: 'PKR'),
      cnyThreshold,
      Decision.propose,
    ),
    (
      'missing assumed requires confirmation',
      'add_expense',
      ToolKind.write,
      preview(2800)..remove('assumed'),
      cnyThreshold,
      Decision.propose,
    ),
    (
      'non-list assumed requires confirmation',
      'add_expense',
      ToolKind.write,
      preview(2800, assumed: ''),
      cnyThreshold,
      Decision.propose,
    ),
    (
      'missing policy amount requires confirmation',
      'add_expense',
      ToolKind.write,
      preview(2800)..remove('policy_amount'),
      cnyThreshold,
      Decision.propose,
    ),
    (
      'non-map policy amount requires confirmation',
      'add_expense',
      ToolKind.write,
      {'assumed': <String>[], 'policy_amount': 2800},
      cnyThreshold,
      Decision.propose,
    ),
    (
      'missing policy currency requires confirmation',
      'add_expense',
      ToolKind.write,
      {
        'assumed': <String>[],
        'policy_amount': {'minor': 2800},
      },
      cnyThreshold,
      Decision.propose,
    ),
    for (final minor in <Object?>[null, '2800', -1])
      (
        'invalid policy minor units ${minor.runtimeType}:$minor require confirmation',
        'add_expense',
        ToolKind.write,
        preview(minor),
        cnyThreshold,
        Decision.propose,
      ),
    (
      '999.99 PKR auto-saves below the 1000 PKR threshold',
      'add_expense',
      ToolKind.write,
      preview(99999, currency: 'PKR'),
      pkrThreshold,
      Decision.autoSave,
    ),
    (
      '1000.00 PKR requires confirmation at the 1000 PKR threshold',
      'add_expense',
      ToolKind.write,
      preview(100000, currency: 'PKR'),
      pkrThreshold,
      Decision.propose,
    ),
  ]) {
    test(name, () {
      expect(
        policy.decide(
          toolName: tool,
          kind: kind,
          preview: data,
          threshold: threshold,
        ),
        expected,
      );
    });
  }
}
