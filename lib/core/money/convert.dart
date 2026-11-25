import 'package:decimal/decimal.dart';

import 'currency.dart';
import 'money.dart';

Decimal crossRate(Decimal fromPerUsd, Decimal toPerUsd) =>
    (toPerUsd / fromPerUsd).toDecimal(scaleOnInfinitePrecision: 32);

final _half = Decimal.parse('0.5');

Money convert(Money m, Decimal rate, String toCurrency) {
  final major = Decimal.fromInt(m.minor)
      .shift(-currencyOf(m.currency).minorDigits);
  final targetMinor = (major * rate).shift(currencyOf(toCurrency).minorDigits);
  final magnitude = (targetMinor.abs() + _half).floor().toBigInt();
  final rounded = targetMinor < Decimal.zero ? -magnitude : magnitude;
  if (!rounded.isValidInt) {
    throw RangeError('Amount exceeds the minor-unit range');
  }
  return Money(rounded.toInt(), toCurrency);
}
