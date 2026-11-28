import 'package:decimal/decimal.dart';

import '../../../core/money/convert.dart';
import '../../../core/money/money.dart';
import '../../../data/db/app_database.dart';
import '../../fx/fx_service.dart';
import '../../ledger/ledger_errors.dart';
import 'tool_args.dart';
import 'tool_registry.dart';
import 'tool_spec.dart';

// Compare how an action will appear, including nested old/new entry previews.
bool previewChanged(Map oldPreview, Map newPreview) {
  Map shown(Map preview) {
    final fields = Map.of(preview)
      ..remove('arguments')
      ..remove('previewed_at')
      ..remove('policy_amount');
    // Only entries show a date. Other actions record when they were previewed.
    if (!fields.containsKey('kind') || !fields.containsKey('account_id')) {
      fields.remove('at');
    }
    return fields;
  }

  return !sameJsonValue(shown(oldPreview), shown(newPreview));
}

bool sameJsonValue(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) => b.containsKey(key) && sameJsonValue(a[key], b[key]),
        );
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        a.indexed.every((item) => sameJsonValue(item.$2, b[item.$1]));
  }
  return a == b;
}

const invalidPreview = ToolError(
  'invalid_preview',
  'Validate the action before executing it.',
);
const _changed = ToolError(
  'changed',
  'The action changed. Review the updated preview.',
);

class WriteAction {
  const WriteAction(this.summary, this.data, this.write);
  final String summary;
  final Map<String, Object?> data;
  final Future<ToolOk> Function() write;
}

void registerWriteTool(
  ToolRegistry registry,
  AppDatabase db,
  String name,
  String description,
  Map<String, String> fields,
  Future<WriteAction> Function(WriteArgs) prepare, {
  List<String> required = const [],
  ToolKind kind = ToolKind.write,
  DateTime Function()? clock,
  bool freezeEntryDate = false,
}) {
  final now = clock ?? DateTime.now;
  Future<(Map<String, Object?>, WriteAction)> build(
    Map<String, Object?> input, {
    DateTime? previewedAt,
  }) async {
    final args = WriteArgs(
      input,
      previewedAt == null ? now : () => previewedAt,
    );
    for (final key in required) {
      if (input[key] == null) throw missingArgument(key);
    }
    final assumed = input['assumed'] == null
        ? <String>[]
        : args.checked<List<String>>(stringList(input, 'assumed'));
    final summary = args.optionalText('summary');
    final action = await prepare(args);
    return (
      {
        'tool': name,
        'at': args.at.toIso8601String(),
        'assumed': assumed,
        'summary': summary == null || summary.trim().isEmpty
            ? action.summary
            : summary.trim(),
        'policy_amount': null,
        ...action.data,
        'previewed_at': args.effectiveInputDate.toIso8601String(),
        'arguments': {
          for (final key in fields.keys)
            if (input.containsKey(key)) key: input[key],
          if (freezeEntryDate) 'at': args.at.toIso8601String(),
          'assumed': assumed,
          'summary': ?summary,
        },
      },
      action,
    );
  }

  Future<ToolResult> guarded(Future<ToolResult> Function() work) async {
    try {
      return await db.transaction(work);
    } on ToolError catch (error) {
      return error;
    } on LedgerException catch (error) {
      return ToolError(error.code, error.message);
    } catch (_) {
      return const ToolError(
        'internal_error',
        'The action could not be completed.',
      );
    }
  }

  registry.register(
    ToolSpec(
      name: name,
      description:
          '$description Send money amounts as decimal strings. List any field Rao did not say in assumed.',
      parameters: {
        'type': 'object',
        'properties': {
          for (final field in fields.entries)
            field.key: {
              'type': field.key.endsWith('_id') ? 'integer' : 'string',
              'description': field.value,
            },
          'assumed': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Fields you inferred.',
          },
          'summary': {
            'type': 'string',
            'description': 'Short summary for Rao.',
          },
        },
        'required': required,
      },
      kind: kind,
      validate: (args) => guarded(() async => ToolOk((await build(args)).$1)),
      execute: (preview) => guarded(() async {
        final input = preview['arguments'];
        if (preview['tool'] != name ||
            input is! Map<String, Object?> ||
            preview['at'] is! String ||
            preview['assumed'] is! List ||
            preview['summary'] is! String ||
            !preview.containsKey('policy_amount')) {
          return invalidPreview;
        }
        final previewedAt = optionalDate(preview, 'previewed_at');
        if (previewedAt is! DateTime) return invalidPreview;
        final (fresh, action) = await build(input, previewedAt: previewedAt);
        if (previewChanged(preview, fresh)) return _changed;
        return action.write();
      }),
    ),
  );
}

class WriteArgs {
  WriteArgs(this.input, this._clock);
  final Map<String, Object?> input;
  final DateTime Function() _clock;
  late final DateTime? date = checkedNullable<DateTime>(
    optionalDate(input, 'at'),
  );
  late final DateTime effectiveInputDate = (date ?? _clock()).toLocal();
  DateTime? entryDate;
  DateTime get at => entryDate ?? effectiveInputDate;

  T checked<T>(Object value) {
    if (value is ToolError) throw value;
    return value as T;
  }

  T? checkedNullable<T>(Object? value) =>
      value == null ? null : checked<T>(value);
  bool has(String name) => input.containsKey(name);
  int id(String name) => checked<int>(intId(input, name));
  String currency([String name = 'currency']) =>
      checked<String>(currencyArg(input, name));

  String text(String name) {
    final value = input[name];
    if (value == null) throw missingArgument(name);
    if (value is String) return value;
    throw ToolError('invalid_argument', '$name must be text.');
  }

  String? optionalText(String name) => input[name] == null ? null : text(name);

  Money amount(String name, String code) {
    final value = input[name];
    if (value == null) throw missingArgument(name);
    if (value is! String) {
      throw ToolError(
        'amount_must_be_string',
        'Send $name as a decimal string.',
      );
    }
    try {
      return Money.parse(value, code);
    } on FormatException {
      throw ToolError(
        'invalid_amount',
        'Enter a valid decimal amount for $name.',
      );
    }
  }

  Decimal? rate() {
    final value = optionalText('rate');
    if (value == null) return null;
    final rate = Decimal.tryParse(value);
    if (rate != null) return rate;
    throw const ToolError('invalid_rate', 'Send rate as a decimal string.');
  }
}

Future<Map<String, Object?>?> policyMoney(
  FxService fx,
  Money amount,
  String currency,
) async {
  if (amount.currency == currency) return moneyJson(amount);
  final rate = await fx.rate(amount.currency, currency);
  return rate == null ? null : moneyJson(convert(amount, rate, currency));
}
