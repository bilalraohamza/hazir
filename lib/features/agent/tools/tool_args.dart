import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import 'tool_spec.dart';

ToolError missingArgument(String name) =>
    ToolError('missing_argument', 'Provide $name.');

Object currencyArg(Map<String, Object?> args, String name) {
  final value = args[name];
  if (value == null) return missingArgument(name);
  if (value is String) {
    try {
      return currencyOf(value).code;
    } on ArgumentError {
      // Report a uniform error for unsupported codes and wrong types.
    }
  }
  return ToolError('unknown_currency', '$name must be CNY, PKR or USD.');
}

Object money(
  Map<String, Object?> args,
  String amountName,
  String currencyName,
) {
  final value = args[amountName];
  if (value == null) return missingArgument(amountName);
  if (value is! String) {
    return ToolError(
      'amount_must_be_string',
      'Send $amountName as a decimal string.',
    );
  }
  final currency = currencyArg(args, currencyName);
  if (currency is ToolError) return currency;
  try {
    final amount = Money.parse(value, currency as String);
    if (amount.minor > 0) return amount;
  } on FormatException {
    // The same error covers malformed and out-of-range amounts.
  }
  return ToolError(
    'invalid_amount',
    '$amountName must be a positive decimal amount.',
  );
}

final _digits = RegExp(r'^[0-9]+$');

Object intId(Map<String, Object?> args, String name) {
  final value = args[name];
  if (value == null) return missingArgument(name);
  if (value is int) return value;
  if (value is String && _digits.hasMatch(value)) {
    final id = int.tryParse(value);
    if (id != null) return id;
  }
  return ToolError(
    'invalid_id',
    '$name must be an integer or a string of digits.',
  );
}

final _localDate = RegExp(
  r'^[0-9]{4}-[0-9]{2}-[0-9]{2}(?:T[0-9]{2}:[0-9]{2}(?::[0-9]{2}(?:\.[0-9]{1,6})?)?)?$',
);

Object? optionalDate(Map<String, Object?> args, String name) {
  final value = args[name];
  if (value == null) return null;
  if (value is String && _localDate.hasMatch(value)) {
    final date = DateTime.tryParse(value);
    // DateTime.parse normalizes overflow. Reject it instead of shifting days.
    final checkLength = value.length < 19 ? value.length : 19;
    if (date != null &&
        date.toIso8601String().startsWith(value.substring(0, checkLength))) {
      return date;
    }
  }
  return ToolError(
    'invalid_date',
    '$name must be a local ISO date or date and time.',
  );
}

Object stringList(Map<String, Object?> args, String name) {
  final value = args[name];
  if (value == null) return missingArgument(name);
  if (value is List && value.every((item) => item is String)) {
    return List<String>.of(value.cast<String>());
  }
  return ToolError('invalid_list', '$name must be a list of strings.');
}

Map<String, Object?> moneyJson(Money value) => {
  'minor': value.minor,
  'currency': value.currency,
  'formatted': formatMoney(value),
};
