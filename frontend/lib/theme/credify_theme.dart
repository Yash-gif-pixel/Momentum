import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens shared by every Credify screen, ported from designs/shared.css.
@immutable
class CredifyTokens extends ThemeExtension<CredifyTokens> {
  final Color bg;
  final Color orb1;
  final Color orb2;
  final double orbOpacity;
  final Color cardFill;
  final Color glassBorder;
  final Color hairline;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accentA;
  final Color accentB;
  final Color pillFill;
  final Color navFill;
  final Color positive;
  final Color warning;
  final Color negative;

  const CredifyTokens({
    required this.bg,
    required this.orb1,
    required this.orb2,
    required this.orbOpacity,
    required this.cardFill,
    required this.glassBorder,
    required this.hairline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accentA,
    required this.accentB,
    required this.pillFill,
    required this.navFill,
    required this.positive,
    required this.warning,
    required this.negative,
  });

  LinearGradient get accentGradient => LinearGradient(
        colors: [accentA, accentB],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static const light = CredifyTokens(
    bg: Color(0xFFF5F5F7),
    orb1: Color(0xFFA2C2E1),
    orb2: Color(0xFFD8C3E5),
    orbOpacity: 0.35,
    cardFill: Color(0xB3FFFFFF),
    glassBorder: Color(0x80FFFFFF),
    hairline: Color(0x14111114),
    textPrimary: Color(0xFF111114),
    textSecondary: Color(0x99111114),
    textTertiary: Color(0x66111114),
    accentA: Color(0xFF6366F1),
    accentB: Color(0xFF10B981),
    pillFill: Color(0x8CFFFFFF),
    navFill: Color(0xA6FFFFFF),
    positive: Color(0xFF059669),
    warning: Color(0xFFD97706),
    negative: Color(0xFFDC2626),
  );

  static const dark = CredifyTokens(
    bg: Color(0xFF000000),
    orb1: Color(0xFF7C3AED),
    orb2: Color(0xFFDB2777),
    orbOpacity: 0.10,
    cardFill: Color(0x0BFFFFFF),
    glassBorder: Color(0x17FFFFFF),
    hairline: Color(0x14FFFFFF),
    textPrimary: Color(0xFFF4F2F7),
    textSecondary: Color(0x8FF4F2F7),
    textTertiary: Color(0x5CF4F2F7),
    accentA: Color(0xFFC084FC),
    accentB: Color(0xFFF472B6),
    pillFill: Color(0xA6100E14),
    navFill: Color(0xB30E0C11),
    positive: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    negative: Color(0xFFFB7185),
  );

  @override
  CredifyTokens copyWith({
    Color? bg,
    Color? orb1,
    Color? orb2,
    double? orbOpacity,
    Color? cardFill,
    Color? glassBorder,
    Color? hairline,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accentA,
    Color? accentB,
    Color? pillFill,
    Color? navFill,
    Color? positive,
    Color? warning,
    Color? negative,
  }) {
    return CredifyTokens(
      bg: bg ?? this.bg,
      orb1: orb1 ?? this.orb1,
      orb2: orb2 ?? this.orb2,
      orbOpacity: orbOpacity ?? this.orbOpacity,
      cardFill: cardFill ?? this.cardFill,
      glassBorder: glassBorder ?? this.glassBorder,
      hairline: hairline ?? this.hairline,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accentA: accentA ?? this.accentA,
      accentB: accentB ?? this.accentB,
      pillFill: pillFill ?? this.pillFill,
      navFill: navFill ?? this.navFill,
      positive: positive ?? this.positive,
      warning: warning ?? this.warning,
      negative: negative ?? this.negative,
    );
  }

  @override
  CredifyTokens lerp(ThemeExtension<CredifyTokens>? other, double t) {
    if (other is! CredifyTokens) return this;
    return CredifyTokens(
      bg: Color.lerp(bg, other.bg, t)!,
      orb1: Color.lerp(orb1, other.orb1, t)!,
      orb2: Color.lerp(orb2, other.orb2, t)!,
      orbOpacity: orbOpacity + (other.orbOpacity - orbOpacity) * t,
      cardFill: Color.lerp(cardFill, other.cardFill, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accentA: Color.lerp(accentA, other.accentA, t)!,
      accentB: Color.lerp(accentB, other.accentB, t)!,
      pillFill: Color.lerp(pillFill, other.pillFill, t)!,
      navFill: Color.lerp(navFill, other.navFill, t)!,
      positive: Color.lerp(positive, other.positive, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
    );
  }
}

extension CredifyThemeX on BuildContext {
  CredifyTokens get tokens => Theme.of(this).extension<CredifyTokens>()!;
}

class CredifyTheme {
  static ThemeData get light => _build(Brightness.light, CredifyTokens.light);
  static ThemeData get dark => _build(Brightness.dark, CredifyTokens.dark);

  static ThemeData _build(Brightness brightness, CredifyTokens t) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: t.bg,
      canvasColor: t.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: t.accentA,
        brightness: brightness,
      ).copyWith(
        primary: t.accentA,
        secondary: t.accentB,
        surface: t.bg,
        onSurface: t.textPrimary,
        error: t.negative,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: t.textPrimary,
        displayColor: t.textPrimary,
      ),
      dividerTheme: DividerThemeData(color: t.hairline, thickness: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accentA),
      extensions: <ThemeExtension<dynamic>>[t],
    );
  }
}
