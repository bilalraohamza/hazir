import 'package:material_ui/material_ui.dart';

import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../theme/app_colors.dart';

class AmountText extends StatelessWidget {
  const AmountText(
    this.m, {
    super.key,
    this.size = 44,
    this.showDecimals = true,
    this.signed = false,
  });

  final Money m;
  final double size;
  final bool showDecimals;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors =
        theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark
            ? AppColors.dark
            : AppColors.light);
    final symbol = currencyOf(m.currency).symbol;
    final formatted = formatMoney(m, signed: signed);
    final symbolStart = formatted.indexOf(symbol);
    final sign = formatted.substring(0, symbolStart);
    final digits = formatted.substring(symbolStart + symbol.length).split('.');
    final decimals = showDecimals && digits.length > 1 ? '.${digits[1]}' : '';

    final style = TextStyle(
      color: colors.ink,
      fontFamily: 'Bricolage',
      fontSize: size,
      fontWeight: FontWeight.w500,
      fontVariations: const [
        FontVariation('wdth', 80),
        FontVariation('wght', 500),
      ],
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final small = style.copyWith(fontSize: size / 2);

    return Semantics(
      label: '$sign$symbol${digits.first}$decimals',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            if (sign.isNotEmpty) TextSpan(text: sign),
            WidgetSpan(
              alignment: PlaceholderAlignment.top,
              child: Text(symbol, style: small),
            ),
            TextSpan(text: digits.first),
            if (decimals.isNotEmpty)
              TextSpan(
                text: decimals,
                style: small.copyWith(color: colors.muted),
              ),
          ],
        ),
        textDirection: TextDirection.ltr,
      ),
    );
  }
}
