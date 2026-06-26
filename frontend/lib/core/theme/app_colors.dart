// app/core/theme/app_colors.dart
// Purpose: Defines the full color palette for Kivo Workspace.
// Responsibilities: Exposes dynamic light and dark theme colors via ThemeExtension.

import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  // --- Light Palette Static Constants ---
  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color lightSidebarBackground = Color(0xFFFBFBFA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFF1F1EF);
  static const Color lightBorder = Color(0xFFEDEDEB);
  static const Color lightDivider = Color(0xFFEDEDEB);

  static const Color lightPrimary = Color(0xFF0075DE);
  static const Color lightPrimaryHover = Color(0xFF005DB2);
  static const Color lightPrimarySubtle = Color(0xFFE7F3F8);

  static const Color lightTextPrimary = Color(0xFF37352F);
  static const Color lightTextSecondary = Color(0xFF787774);
  static const Color lightTextMuted = Color(0xFF9B9B9B);

  static const Color lightStatusReady = Color(0xFF0F7B44);
  static const Color lightStatusReadyBg = Color(0xFFEDF3EC);
  static const Color lightStatusProcessing = Color(0xFFD9730D);
  static const Color lightStatusProcessingBg = Color(0xFFFFF1E6);
  static const Color lightStatusFailed = Color(0xFFBA1A1A);
  static const Color lightStatusFailedBg = Color(0xFFFFECEB);
  static const Color lightStatusCancelled = Color(0xFF787774);

  // --- Dark Palette Static Constants ---
  static const Color darkBackground = Color(0xFF191919);
  static const Color darkSidebarBackground = Color(0xFF202020);
  static const Color darkSurface = Color(0xFF202020);
  static const Color darkSurfaceElevated = Color(0xFF252525);
  static const Color darkBorder = Color(0xFF2F2F2F);
  static const Color darkDivider = Color(0xFF2F2F2F);

  static const Color darkPrimary = Color(0xFF0075DE);
  static const Color darkPrimaryHover = Color(0xFF005DB2);
  static const Color darkPrimarySubtle = Color(0xFF1B2A32);

  static const Color darkTextPrimary = Color(0xFFE3E2E0);
  static const Color darkTextSecondary = Color(0xFF9B9B9B);
  static const Color darkTextMuted = Color(0xFF5F5E5B);

  static const Color darkStatusReady = Color(0xFF4DAB76);
  static const Color darkStatusReadyBg = Color(0xFF1C3D2E);
  static const Color darkStatusProcessing = Color(0xFFE18D34);
  static const Color darkStatusProcessingBg = Color(0xFF3D2B1E);
  static const Color darkStatusFailed = Color(0xFFFF7373);
  static const Color darkStatusFailedBg = Color(0xFF3F1E1E);
  static const Color darkStatusCancelled = Color(0xFF9B9B9B);

  // --- Instance Properties ---
  final Color background;
  final Color sidebarBackground;
  final Color surface;
  final Color surfaceElevated;
  final Color border;
  final Color divider;
  final Color primary;
  final Color primaryHover;
  final Color primarySubtle;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color statusReady;
  final Color statusReadyBg;
  final Color statusProcessing;
  final Color statusProcessingBg;
  final Color statusFailed;
  final Color statusFailedBg;
  final Color statusCancelled;

  const AppColors({
    required this.background,
    required this.sidebarBackground,
    required this.surface,
    required this.surfaceElevated,
    required this.border,
    required this.divider,
    required this.primary,
    required this.primaryHover,
    required this.primarySubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.statusReady,
    required this.statusReadyBg,
    required this.statusProcessing,
    required this.statusProcessingBg,
    required this.statusFailed,
    required this.statusFailedBg,
    required this.statusCancelled,
  });

  @override
  AppColors copyWith({
    Color? background,
    Color? sidebarBackground,
    Color? surface,
    Color? surfaceElevated,
    Color? border,
    Color? divider,
    Color? primary,
    Color? primaryHover,
    Color? primarySubtle,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? statusReady,
    Color? statusReadyBg,
    Color? statusProcessing,
    Color? statusProcessingBg,
    Color? statusFailed,
    Color? statusFailedBg,
    Color? statusCancelled,
  }) {
    return AppColors(
      background: background ?? this.background,
      sidebarBackground: sidebarBackground ?? this.sidebarBackground,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      primary: primary ?? this.primary,
      primaryHover: primaryHover ?? this.primaryHover,
      primarySubtle: primarySubtle ?? this.primarySubtle,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      statusReady: statusReady ?? this.statusReady,
      statusReadyBg: statusReadyBg ?? this.statusReadyBg,
      statusProcessing: statusProcessing ?? this.statusProcessing,
      statusProcessingBg: statusProcessingBg ?? this.statusProcessingBg,
      statusFailed: statusFailed ?? this.statusFailed,
      statusFailedBg: statusFailedBg ?? this.statusFailedBg,
      statusCancelled: statusCancelled ?? this.statusCancelled,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) {
      return this;
    }
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      sidebarBackground: Color.lerp(sidebarBackground, other.sidebarBackground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryHover: Color.lerp(primaryHover, other.primaryHover, t)!,
      primarySubtle: Color.lerp(primarySubtle, other.primarySubtle, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      statusReady: Color.lerp(statusReady, other.statusReady, t)!,
      statusReadyBg: Color.lerp(statusReadyBg, other.statusReadyBg, t)!,
      statusProcessing: Color.lerp(statusProcessing, other.statusProcessing, t)!,
      statusProcessingBg: Color.lerp(statusProcessingBg, other.statusProcessingBg, t)!,
      statusFailed: Color.lerp(statusFailed, other.statusFailed, t)!,
      statusFailedBg: Color.lerp(statusFailedBg, other.statusFailedBg, t)!,
      statusCancelled: Color.lerp(statusCancelled, other.statusCancelled, t)!,
    );
  }

  // --- Light Palette ---
  static const AppColors light = AppColors(
    background: lightBackground,
    sidebarBackground: lightSidebarBackground,
    surface: lightSurface,
    surfaceElevated: lightSurfaceElevated,
    border: lightBorder,
    divider: lightDivider,
    primary: lightPrimary,
    primaryHover: lightPrimaryHover,
    primarySubtle: lightPrimarySubtle,
    textPrimary: lightTextPrimary,
    textSecondary: lightTextSecondary,
    textMuted: lightTextMuted,
    statusReady: lightStatusReady,
    statusReadyBg: lightStatusReadyBg,
    statusProcessing: lightStatusProcessing,
    statusProcessingBg: lightStatusProcessingBg,
    statusFailed: lightStatusFailed,
    statusFailedBg: lightStatusFailedBg,
    statusCancelled: lightStatusCancelled,
  );

  // --- Dark Palette ---
  static const AppColors dark = AppColors(
    background: darkBackground,
    sidebarBackground: darkSidebarBackground,
    surface: darkSurface,
    surfaceElevated: darkSurfaceElevated,
    border: darkBorder,
    divider: darkDivider,
    primary: darkPrimary,
    primaryHover: darkPrimaryHover,
    primarySubtle: darkPrimarySubtle,
    textPrimary: darkTextPrimary,
    textSecondary: darkTextSecondary,
    textMuted: darkTextMuted,
    statusReady: darkStatusReady,
    statusReadyBg: darkStatusReadyBg,
    statusProcessing: darkStatusProcessing,
    statusProcessingBg: darkStatusProcessingBg,
    statusFailed: darkStatusFailed,
    statusFailedBg: darkStatusFailedBg,
    statusCancelled: darkStatusCancelled,
  );
}

extension ThemeContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>() ?? AppColors.light;
}
