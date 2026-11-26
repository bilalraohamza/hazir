import 'package:material_ui/material_ui.dart';

class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.ground,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.rule,
    required this.brass,
    required this.onBrass,
    required this.yuan,
    required this.rupee,
    required this.dollar,
    required this.gain,
    required this.warning,
  });

  final Color ground, surface, ink, muted, rule, brass, onBrass;
  final Color yuan, rupee, dollar, gain, warning;

  static const light = AppColors(
    ground: Color(0xFFEEF1EC),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF15201B),
    muted: Color(0xFF5E6B64),
    rule: Color(0xFFD5DCD6),
    brass: Color(0xFFE8B83A),
    onBrass: Color(0xFF15201B),
    yuan: Color(0xFFC8463A),
    rupee: Color(0xFF2F8F5B),
    dollar: Color(0xFF5F8696),
    gain: Color(0xFF2F7A4F),
    warning: Color(0xFFA32D2D),
  );

  static const dark = AppColors(
    ground: Color(0xFF0E1613),
    surface: Color(0xFF17221D),
    ink: Color(0xFFE6ECE7),
    muted: Color(0xFF8C9A92),
    rule: Color(0xFF28352F),
    brass: Color(0xFFE8B83A),
    onBrass: Color(0xFF15201B),
    yuan: Color(0xFFE0705F),
    rupee: Color(0xFF5DBE88),
    dollar: Color(0xFF8FB3C2),
    gain: Color(0xFF7FD1A0),
    warning: Color(0xFFF09595),
  );

  @override
  AppColors copyWith({
    Color? ground,
    Color? surface,
    Color? ink,
    Color? muted,
    Color? rule,
    Color? brass,
    Color? onBrass,
    Color? yuan,
    Color? rupee,
    Color? dollar,
    Color? gain,
    Color? warning,
  }) => AppColors(
    ground: ground ?? this.ground,
    surface: surface ?? this.surface,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    rule: rule ?? this.rule,
    brass: brass ?? this.brass,
    onBrass: onBrass ?? this.onBrass,
    yuan: yuan ?? this.yuan,
    rupee: rupee ?? this.rupee,
    dollar: dollar ?? this.dollar,
    gain: gain ?? this.gain,
    warning: warning ?? this.warning,
  );

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      ground: Color.lerp(ground, other.ground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      brass: Color.lerp(brass, other.brass, t)!,
      onBrass: Color.lerp(onBrass, other.onBrass, t)!,
      yuan: Color.lerp(yuan, other.yuan, t)!,
      rupee: Color.lerp(rupee, other.rupee, t)!,
      dollar: Color.lerp(dollar, other.dollar, t)!,
      gain: Color.lerp(gain, other.gain, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

Color currencyColor(AppColors c, String code) => switch (code) {
  'CNY' => c.yuan,
  'PKR' => c.rupee,
  'USD' => c.dollar,
  _ => c.muted,
};
