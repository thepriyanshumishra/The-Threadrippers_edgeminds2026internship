// core/theme/font_provider.dart
// Purpose: Manages global font family selection (Sans-Serif, Serif, Monospace).

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppFontFamily {
  sans,
  serif,
  mono,
}

final fontProvider = StateProvider<AppFontFamily>((ref) {
  return AppFontFamily.sans;
});
