// main.dart
// Purpose: Application entry point for Kivo Workspace.
// Responsibilities: Wraps the app in a ProviderScope for Riverpod and launches.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: KivoApp(),
    ),
  );
}
