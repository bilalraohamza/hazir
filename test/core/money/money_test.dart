import 'package:budget_app/core/money/currency.dart';
import 'package:budget_app/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parse and format', () {
    expect(Money.parse('28', 'CNY').minor, 2800);
    expect(Money.parse('28.5', 'CNY').minor, 2850);
    expect(Money.parse('1,200.5', 'CNY').minor, 120050);
    expect(Money.parse('1,200.00', 'CNY').minor, 120000);
    expect(() => Money.parse('1.234', 'CNY'), throwsFormatException);
    expect(formatMoney(Money(842050, 'CNY')), '¥8,420.50');
    expect(
      formatMoney(Money(-2800, 'CNY'), withSymbol: false, signed: true),
      '−28.00',
    );
  });

  test('parse rejects malformed amounts', () {
    for (final text in ['', 'abc', '1.2.3', '12,00']) {
      expect(
        () => Money.parse(text, 'CNY'),
        throwsFormatException,
        reason: text,
      );
    }
  });

  test('formatMoney uses PKR and USD symbols', () {
    expect(formatMoney(Money(123456, 'PKR')), '₨1,234.56');
    expect(formatMoney(Money(5, 'USD')), r'$0.05');
  });

  test('add rejects mixed currency', () {
    expect(() => Money(1, 'CNY') + Money(1, 'PKR'), throwsArgumentError);
  });

  test('money arithmetic and equality preserve currency', () {
    final one = Money(100, 'USD');
    final two = one + one;
    expect(two, Money(200, 'USD'));
    expect(two.hashCode, Money(200, 'USD').hashCode);
    expect(two, isNot(Money(200, 'CNY')));
    expect((one - two).isNegative, isTrue);
    expect(() => one - Money(100, 'PKR'), throwsArgumentError);
  });

  test('currencyOf rejects unknown codes', () {
    expect(() => currencyOf('XYZ'), throwsArgumentError);
  });

  test('money preserves large amounts and rejects overflow', () {
    final max = Money.parse('92233720368547758.07', 'USD');
    expect(formatMoney(max), r'$92,233,720,368,547,758.07');
    expect(() => max + Money(1, 'USD'), throwsRangeError);
    expect(
      () => Money.parse('92233720368547758.08', 'USD'),
      throwsFormatException,
    );
  });
}
