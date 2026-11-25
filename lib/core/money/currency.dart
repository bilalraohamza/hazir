class Currency {
  const Currency(this.code, this.minorDigits, this.symbol);

  final String code;
  final int minorDigits;
  final String symbol;
}

const _currencies = {
  'CNY': Currency('CNY', 2, '¥'),
  'PKR': Currency('PKR', 2, '₨'),
  'USD': Currency('USD', 2, r'$'),
};

Currency currencyOf(String code) =>
    _currencies[code] ??
    (throw ArgumentError.value(code, 'code', 'Unknown currency'));
