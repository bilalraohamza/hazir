import 'package:budget_app/core/money/convert.dart';
import 'package:budget_app/core/money/money.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('convert rounds half up, no truncation', () {
    final cnyPerPkr = crossRate(Decimal.parse('281.5'), Decimal.parse('7.1'));
    expect(convert(Money(100, 'PKR'), cnyPerPkr, 'CNY').minor, 3);
    expect(convert(Money(500000, 'PKR'), cnyPerPkr, 'CNY').minor, 12611);
  });

  test('convert rounds positive and negative half-fen symmetrically', () {
    final half = Decimal.parse('0.5');
    expect(convert(Money(1, 'PKR'), half, 'CNY'), Money(1, 'CNY'));
    expect(convert(Money(-1, 'PKR'), half, 'CNY'), Money(-1, 'CNY'));
    expect(convert(Money(-1, 'PKR'), Decimal.parse('0.4999'), 'CNY').minor, 0);
  });

  test('crossRate retains at least twelve decimal places', () {
    final rate = crossRate(Decimal.fromInt(3), Decimal.one);
    expect(rate.toStringAsFixed(12), '0.333333333333');
  });
}
