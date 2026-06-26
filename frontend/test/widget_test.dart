// test/widget_test.dart
// Purpose: Sprint 0 smoke test — verifies the app mounts without crashing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_workspace/app.dart';

void main() {
  testWidgets('App mounts without errors', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: KivoApp(),
      ),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
