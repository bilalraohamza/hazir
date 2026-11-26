import 'package:material_ui/material_ui.dart';

import 'app_colors.dart';

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final c = dark ? AppColors.dark : AppColors.light;
  final scheme = ColorScheme(
    brightness: b,
    primary: c.brass,
    onPrimary: c.onBrass,
    secondary: c.ink,
    onSecondary: c.surface,
    secondaryContainer: c.brass,
    onSecondaryContainer: c.onBrass,
    error: c.warning,
    onError: dark ? c.onBrass : c.surface,
    errorContainer: c.surface,
    onErrorContainer: c.warning,
    surface: c.surface,
    onSurface: c.ink,
    onSurfaceVariant: c.muted,
    surfaceDim: c.ground,
    surfaceContainerLow: c.ground,
    outline: c.muted,
    outlineVariant: c.rule,
    shadow: c.onBrass,
    scrim: c.onBrass,
    inverseSurface: c.ink,
    onInverseSurface: c.surface,
    inversePrimary: c.surface,
    surfaceTint: c.surface,
  );
  final text = _instrumentText(c.ink);
  final pressed = c.ink.withValues(alpha: 0.12);
  final hover = c.ink.withValues(alpha: 0.04);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: [c],
    scaffoldBackgroundColor: c.ground,
    canvasColor: c.ground,
    primaryColorLight: c.surface,
    primaryColorDark: c.onBrass,
    secondaryHeaderColor: c.ground,
    shadowColor: c.onBrass,
    dividerColor: c.rule,
    hintColor: c.muted,
    disabledColor: c.muted,
    unselectedWidgetColor: c.muted,
    focusColor: pressed,
    hoverColor: hover,
    highlightColor: pressed,
    splashColor: pressed,
    buttonTheme: ButtonThemeData(buttonColor: c.brass, colorScheme: scheme),
    iconTheme: IconThemeData(color: c.ink),
    primaryIconTheme: IconThemeData(color: dark ? c.ink : c.onBrass),
    fontFamily: 'Instrument',
    textTheme: text,
    primaryTextTheme: dark ? text : _instrumentText(c.onBrass),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.ink),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        side: BorderSide(color: c.brass),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(foregroundColor: c.ink),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.ink,
      selectionColor: c.rule,
      selectionHandleColor: c.ink,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      floatingLabelStyle: text.bodyLarge!.copyWith(color: c.ink),
    ),
  );
}

TextTheme _instrumentText(Color ink) {
  const base = Typography.englishLike2021;

  TextStyle style(TextStyle original, {bool medium = false}) =>
      original.copyWith(
        color: ink,
        fontFamily: 'Instrument',
        fontWeight: medium ? FontWeight.w500 : FontWeight.w400,
        fontVariations: medium
            ? const [FontVariation('wght', 500)]
            : const [FontVariation('wght', 400)],
      );

  return TextTheme(
    displayLarge: style(base.displayLarge!),
    displayMedium: style(base.displayMedium!),
    displaySmall: style(base.displaySmall!),
    headlineLarge: style(base.headlineLarge!),
    headlineMedium: style(base.headlineMedium!),
    headlineSmall: style(base.headlineSmall!),
    titleLarge: style(base.titleLarge!),
    titleMedium: style(base.titleMedium!, medium: true),
    titleSmall: style(base.titleSmall!, medium: true),
    bodyLarge: style(base.bodyLarge!),
    bodyMedium: style(base.bodyMedium!),
    bodySmall: style(base.bodySmall!),
    labelLarge: style(base.labelLarge!, medium: true),
    labelMedium: style(base.labelMedium!, medium: true),
    labelSmall: style(base.labelSmall!, medium: true),
  );
}
