/// core/theme.dart — the app theme, built from the shared coffee palette.
///
/// The colours come from CoffeePalette (see constants.dart), which holds the
/// same hex values as the desktop app, so a café running both sees one product
/// rather than two designs.
///
/// TYPE SCALE: Arabic needs more line height than Latin at the same size — the
/// diacritics and the taller ascenders clip at a tight `height`, so every style
/// here sets one explicitly. The bundled Noto Naskh face is applied globally so
/// the app does not depend on what Arabic font the OEM shipped.
library;

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'constants.dart';

/// The app font, declared in pubspec.yaml and bundled so it renders offline.
const String arabicFontFamily = 'NotoNaskhArabic';

/// Arabic reads better with a little more line height than the Material
/// default, which clips the diacritics.
const double _arabicLineHeight = 1.5;

/// Build the dark (default) theme.
ThemeData buildDarkTheme() => _build(Brightness.dark);

/// Build the light theme.
ThemeData buildLightTheme() => _build(Brightness.light);

ThemeData _build(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  final background =
      Color(isDark ? CoffeePalette.darkBg : CoffeePalette.lightBg);
  final surface =
      Color(isDark ? CoffeePalette.darkSurface : CoffeePalette.lightSurface);
  final surfaceAlt = Color(
      isDark ? CoffeePalette.darkSurfaceAlt : CoffeePalette.lightSurfaceAlt);
  final border =
      Color(isDark ? CoffeePalette.darkBorder : CoffeePalette.lightBorder);
  final text = Color(isDark ? CoffeePalette.darkText : CoffeePalette.lightText);
  final textMuted = Color(
      isDark ? CoffeePalette.darkTextMuted : CoffeePalette.lightTextMuted);
  const accent = Color(CoffeePalette.accent);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: accent,
    onPrimary: const Color(0xFF1A1410),
    secondary: const Color(CoffeePalette.accentHover),
    onSecondary: const Color(0xFF1A1410),
    error: const Color(CoffeePalette.danger),
    onError: Colors.white,
    surface: surface,
    onSurface: text,
    surfaceContainerHighest: surfaceAlt,
    outline: border,
    outlineVariant: Color(
        isDark ? CoffeePalette.darkBorderStrong : CoffeePalette.lightBorder),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    fontFamily: arabicFontFamily,
  );

  return base.copyWith(
    textTheme: _textTheme(base.textTheme, text, textMuted),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: arabicFontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: _arabicLineHeight,
        color: text,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sizes.radius),
        side: BorderSide(color: border),
      ),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    // Every button is at least the accessibility minimum; the POS primary
    // actions set their own larger height on top of this.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: const Color(0xFF1A1410),
        minimumSize: const Size(0, Sizes.minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Sizes.radiusSmall),
        ),
        textStyle: const TextStyle(
          fontFamily: arabicFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          height: _arabicLineHeight,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        minimumSize: const Size(0, Sizes.minTouchTarget),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Sizes.radiusSmall),
        ),
        textStyle: const TextStyle(
          fontFamily: arabicFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: _arabicLineHeight,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        minimumSize: const Size(0, Sizes.minTouchTarget),
        textStyle: const TextStyle(
          fontFamily: arabicFontFamily,
          fontSize: 16,
          height: _arabicLineHeight,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceAlt,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sizes.radiusSmall),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sizes.radiusSmall),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sizes.radiusSmall),
        borderSide: const BorderSide(color: accent, width: 2),
      ),
      labelStyle: TextStyle(
          fontFamily: arabicFontFamily, color: textMuted, height: _arabicLineHeight),
      hintStyle: TextStyle(
          fontFamily: arabicFontFamily, color: textMuted, height: _arabicLineHeight),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: const Color(CoffeePalette.accentSoft),
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontFamily: arabicFontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: _arabicLineHeight,
          color: text,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sizes.radius),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surfaceAlt,
      contentTextStyle: TextStyle(
          fontFamily: arabicFontFamily, color: text, height: _arabicLineHeight),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sizes.radiusSmall),
      ),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: TextStyle(
          fontFamily: arabicFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: _arabicLineHeight,
          color: text),
      subtitleTextStyle: TextStyle(
          fontFamily: arabicFontFamily,
          fontSize: 14,
          height: _arabicLineHeight,
          color: textMuted),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: surfaceAlt,
      side: BorderSide(color: border),
      labelStyle: TextStyle(
          fontFamily: arabicFontFamily, color: text, height: _arabicLineHeight),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent),
  );
}

TextTheme _textTheme(TextTheme base, Color text, Color muted) {
  TextStyle style(double size, FontWeight weight, {Color? color}) => TextStyle(
        fontFamily: arabicFontFamily,
        fontSize: size,
        fontWeight: weight,
        height: _arabicLineHeight,
        color: color ?? text,
      );

  return base.copyWith(
    displayLarge: style(48, FontWeight.w700),
    displayMedium: style(38, FontWeight.w700),
    displaySmall: style(30, FontWeight.w700),
    headlineLarge: style(26, FontWeight.w700),
    headlineMedium: style(22, FontWeight.w700),
    headlineSmall: style(20, FontWeight.w700),
    titleLarge: style(19, FontWeight.w700),
    titleMedium: style(17, FontWeight.w600),
    titleSmall: style(15, FontWeight.w600),
    bodyLarge: style(16, FontWeight.w400),
    bodyMedium: style(15, FontWeight.w400),
    bodySmall: style(13, FontWeight.w400, color: muted),
    labelLarge: style(15, FontWeight.w600),
    labelMedium: style(13, FontWeight.w600, color: muted),
    labelSmall: style(12, FontWeight.w500, color: muted),
  );
}

/// A money figure: tabular, tight line height, and LTR even inside an RTL
/// layout so `2,500 ر.ي` never renders as `ر.ي 2,500`.
TextStyle moneyStyle(BuildContext context, {double size = 18, bool strong = true}) =>
    TextStyle(
      fontFamily: arabicFontFamily,
      fontSize: size,
      fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
      height: 1.3,
      color: Theme.of(context).colorScheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
