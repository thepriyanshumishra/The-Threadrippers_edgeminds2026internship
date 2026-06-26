// app/core/theme/app_theme.dart
// Purpose: Defines the Material ThemeData for Kivo Workspace.
// Responsibilities: Provides light and dark themes with dynamic font support (Sans, Serif, Mono).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'font_provider.dart';

class AppTheme {
  AppTheme._();

  static TextStyle getTextStyle(AppFontFamily fontFamily, {
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
  }) {
    switch (fontFamily) {
      case AppFontFamily.sans:
        return GoogleFonts.inter(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          letterSpacing: letterSpacing,
        );
      case AppFontFamily.serif:
        return GoogleFonts.lora(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          letterSpacing: letterSpacing,
        );
      case AppFontFamily.mono:
        return GoogleFonts.jetBrainsMono(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          letterSpacing: letterSpacing,
        );
    }
  }

  static TextTheme getTextTheme(AppFontFamily fontFamily, TextTheme baseTheme) {
    switch (fontFamily) {
      case AppFontFamily.sans:
        return GoogleFonts.interTextTheme(baseTheme);
      case AppFontFamily.serif:
        return GoogleFonts.loraTextTheme(baseTheme);
      case AppFontFamily.mono:
        return GoogleFonts.jetBrainsMonoTextTheme(baseTheme);
    }
  }

  static ThemeData themeFor(AppFontFamily fontFamily, {required bool isDark, Color? accentColor}) {
    var colors = isDark ? AppColors.dark : AppColors.light;
    if (accentColor != null) {
      colors = colors.copyWith(
        primary: accentColor,
        primaryHover: accentColor,
      );
    }
    final baseTextTheme = isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,

      // --- Color Scheme ---
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: colors.primary,
        onPrimary: isDark ? Colors.black : Colors.white,
        secondary: colors.primary,
        onSecondary: isDark ? Colors.black : Colors.white,
        error: colors.statusFailed,
        onError: Colors.white,
        surface: colors.surface,
        onSurface: colors.textPrimary,
        outline: colors.border,
      ),

      // --- Scaffold ---
      scaffoldBackgroundColor: colors.background,

      // --- Typography ---
      textTheme: getTextTheme(fontFamily, baseTextTheme).apply(
        bodyColor: colors.textPrimary,
        displayColor: colors.textPrimary,
      ),

      // --- AppBar ---
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: getTextStyle(
          fontFamily,
          color: colors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: colors.textSecondary),
      ),

      // --- Divider ---
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1,
        space: 1,
      ),

      // --- Card ---
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.border, width: 1),
        ),
      ),

      // --- Elevated Button ---
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: isDark ? Colors.black : Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          textStyle: getTextStyle(
            fontFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // --- Text Button ---
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          textStyle: getTextStyle(
            fontFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // --- Outlined Button ---
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textSecondary,
          side: BorderSide(color: colors.border),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          textStyle: getTextStyle(
            fontFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // --- Input Field ---
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceElevated,
        hintStyle: getTextStyle(
          fontFamily,
          color: colors.textMuted,
          fontSize: 13.5,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: colors.primary, width: 1.0),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),

      // --- Theme Extensions ---
      extensions: [
        colors,
      ],
    );
  }
}
