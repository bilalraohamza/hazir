import 'dart:math' as math;

import 'package:budget_app/core/money/money.dart';
import 'package:budget_app/ui/theme/app_colors.dart';
import 'package:budget_app/ui/theme/app_theme.dart';
import 'package:budget_app/ui/widgets/amount_text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  test('both palettes preserve brass and accessible text contrast', () {
    expect(AppColors.light.brass, AppColors.dark.brass);
    for (final c in [AppColors.light, AppColors.dark]) {
      expect(c.brass, const Color(0xFFE8B83A));
      expect(c.onBrass, const Color(0xFF15201B));
      expect(contrast(c.onBrass, c.brass), greaterThanOrEqualTo(4.5));
      for (final background in [c.ground, c.surface]) {
        for (final foreground in [c.ink, c.muted]) {
          expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
        }
      }
      expect(
        [
          for (final code in ['CNY', 'PKR', 'USD', 'EUR'])
            currencyColor(c, code),
        ],
        [c.yuan, c.rupee, c.dollar, c.muted],
      );
    }
  });

  test(
    'Material themes expose the palette and use Instrument variable weights',
    () {
      expect(
        buildTheme(Brightness.dark).extension<AppColors>()!.ground,
        const Color(0xFF0E1613),
      );
      for (final brightness in Brightness.values) {
        final theme = buildTheme(brightness);
        final c = brightness == Brightness.light
            ? AppColors.light
            : AppColors.dark;
        expect(theme.scaffoldBackgroundColor, c.ground);
        expect(theme.colorScheme.primary, c.brass);
        expect(theme.colorScheme.onPrimary, c.onBrass);
        expect(theme.colorScheme.surface, c.surface);
        expect(theme.colorScheme.onSurface, c.ink);
        expect(theme.colorScheme.error, c.warning);
        for (final text in [theme.textTheme, theme.primaryTextTheme]) {
          for (final style in [
            text.displayLarge!,
            text.displayMedium!,
            text.displaySmall!,
            text.headlineLarge!,
            text.headlineMedium!,
            text.headlineSmall!,
            text.titleLarge!,
            text.titleMedium!,
            text.titleSmall!,
            text.bodyLarge!,
            text.bodyMedium!,
            text.bodySmall!,
            text.labelLarge!,
            text.labelMedium!,
            text.labelSmall!,
          ]) {
            expect(style.fontFamily, 'Instrument');
            expect(style.fontWeight, isIn([FontWeight.w400, FontWeight.w500]));
            expect(
              style.fontVariations,
              contains(
                FontVariation('wght', style.fontWeight!.value.toDouble()),
              ),
            );
          }
        }
      }
    },
  );

  testWidgets(
    'AmountText raises the yen symbol and renders grouped tabular digits with muted decimals',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const Scaffold(body: AmountText(Money(842050, 'CNY'))),
        ),
      );
      final amount = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(AmountText),
              matching: find.byType(Text),
            ),
          )
          .singleWhere((text) => text.textSpan != null);
      final root = amount.textSpan! as TextSpan;
      final digits = root.children!.whereType<TextSpan>().singleWhere(
        (s) => s.text == '8,420',
      );
      final decimals = root.children!.whereType<TextSpan>().singleWhere(
        (s) => s.text == '.50',
      );
      final style = root.style!.merge(digits.style);
      expect(style.fontFamily, 'Bricolage');
      expect(style.fontSize, 44);
      expect(style.fontWeight, FontWeight.w500);
      expect(
        style.fontVariations,
        containsAll([
          const FontVariation('wdth', 80),
          const FontVariation('wght', 500),
        ]),
      );
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(decimals.style!.fontSize, 22);
      expect(decimals.style!.color, AppColors.light.muted);
      expect(tester.widget<Text>(find.text('¥')).style!.fontSize, 22);
      expect(
        root.children!.whereType<WidgetSpan>().single.alignment,
        PlaceholderAlignment.top,
      );
    },
  );

  testWidgets('hero minus is full digit size and preserves signed formatting', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const Scaffold(
          body: AmountText(
            Money(-2800, 'PKR'),
            size: 32,
            signed: true,
            showDecimals: false,
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('−₨28'), findsOneWidget);
    final richText = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(AmountText),
            matching: find.byType(Text),
          ),
        )
        .singleWhere((widget) => widget.textSpan != null);
    final root = richText.textSpan! as TextSpan;
    final children = root.children!;
    expect(
      children.first,
      isA<TextSpan>().having((span) => span.text, 'sign', '−'),
    );
    final sign = children.first as TextSpan;
    final digits = children.whereType<TextSpan>().singleWhere(
      (span) => span.text == '28',
    );
    expect(
      root.style!.merge(sign.style).fontSize,
      root.style!.merge(digits.style).fontSize,
    );
    expect(find.text('₨'), findsOneWidget);
  });

  testWidgets('small amounts keep the signed symbol inline and mute zeros', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Scaffold(
          body: Column(
            children: [
              AmountText(Money(-2800, 'CNY'), size: 16),
              AmountText(Money(0, 'CNY'), size: 16),
            ],
          ),
        ),
      ),
    );
    final spans = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(AmountText),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.textSpan! as TextSpan)
        .toList();
    final negative = spans.first;
    expect(negative.toPlainText(), '−¥28.00');
    expect(negative.style!.fontSize, 16);
    expect(negative.children!.whereType<WidgetSpan>(), isEmpty);
    expect(negative.children!.last.style!.color, AppColors.light.muted);
    expect(spans.last.style!.color, AppColors.light.muted);
  });
}
