// app.dart
// Purpose: Root application widget for Kivo Workspace.
// Responsibilities: Wires the Riverpod scope, theme, and go_router together.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/font_provider.dart';
import 'core/theme/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/utils/eyedropper_helper.dart';

class KivoApp extends ConsumerWidget {
  const KivoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeFont = ref.watch(fontProvider);
    final activeTheme = ref.watch(themeModeProvider);
    final activeAccent = ref.watch(accentColorProvider);

    return MaterialApp.router(
      title: 'Kivo Workspace',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeFor(activeFont, isDark: false, accentColor: activeAccent),
      darkTheme: AppTheme.themeFor(activeFont, isDark: true, accentColor: activeAccent),
      themeMode: activeTheme,
      routerConfig: appRouter,
      builder: (context, child) {
        return RepaintBoundary(
          key: appRepaintKey,
          child: child,
        );
      },
    );
  }
}
