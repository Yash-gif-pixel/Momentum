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

  /// Light mode: ivory background with gold accents.
  static const light = CredifyTokens(
    bg: Color(0xFFFBF7EB), // ivory
    orb1: Color(0xFFE9D7A0), // pale gold
    orb2: Color(0xFFF3E4C4), // champagne
    orbOpacity: 0.35,
    cardFill: Color(0xB3FFFDF6),
    glassBorder: Color(0x99FFFFFF),
    hairline: Color(0x1F6B5420),
    textPrimary: Color(0xFF221C10),
    textSecondary: Color(0x99221C10),
    textTertiary: Color(0x66221C10),
    accentA: Color(0xFFB8860B), // dark goldenrod
    accentB: Color(0xFFD4AF37), // metallic gold
    pillFill: Color(0x8CFFFDF6),
    navFill: Color(0xB3FFFDF6),
    positive: Color(0xFF2F7D4F),
    warning: Color(0xFFC2620A),
    negative: Color(0xFFB42318),
  );

  static const dark = CredifyTokens(
    bg: Color(0xFF08070B), // the landing page's deep black
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
