import 'package:decimal/decimal.dart';

import 'currency.dart';

class Money {
  const Money(this.minor, this.currency);

  final int minor;
  final String currency;

  bool get isNegative => minor < 0;

  static final _amount = RegExp(
    r'^[+-]?(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.([0-9]+))?$',
  );

  static Money parse(String text, String currency) {
    final digits = currencyOf(currency).minorDigits;
    final input = text.trim().replaceFirst(RegExp(r'^−'), '-');
    final match = _amount.firstMatch(input);
    if (match == null || (match.group(1)?.length ?? 0) > digits) {
      throw FormatException('Invalid amount for $currency', text);
    }
    final minor = Decimal.parse(input.replaceAll(',', ''))
        .shift(digits)
        .toBigInt();
    if (!minor.isValidInt) {
      throw FormatException('Amount exceeds the minor-unit range', text);
    }
    return Money(minor.toInt(), currency);
  }

  Decimal _minorInSameCurrency(Money other) {
    if (currency != other.currency) {
      throw ArgumentError('Currency mismatch: $currency and ${other.currency}');
    }
    return Decimal.fromInt(other.minor);
  }

  Money _result(Decimal minorUnits) {
    final value = minorUnits.toBigInt();
    if (!value.isValidInt) {
      throw RangeError('Amount exceeds the minor-unit range');
    }
    return Money(value.toInt(), currency);
  }

  Money operator +(Money other) =>
      _result(Decimal.fromInt(minor) + _minorInSameCurrency(other));
  Money operator -(Money other) =>
      _result(Decimal.fromInt(minor) - _minorInSameCurrency(other));

  @override
  bool operator ==(Object other) =>
      other is Money && minor == other.minor && currency == other.currency;

  @override
  int get hashCode => Object.hash(minor, currency);
}

String formatMoney(Money m, {bool withSymbol = true, bool signed = false}) {
  final currency = currencyOf(m.currency);
  final amount = Decimal.fromInt(m.minor).abs().shift(-currency.minorDigits);
  final parts = amount.toStringAsFixed(currency.minorDigits).split('.');
  parts[0] = parts[0].replaceAll(RegExp(r'\B(?=(?:[0-9]{3})+$)'), ',');
  final sign = m.isNegative ? '−' : (signed && m.minor > 0 ? '+' : '');
  final symbol = withSymbol ? currency.symbol : '';
  return '$sign$symbol${parts.join('.')}';
}
