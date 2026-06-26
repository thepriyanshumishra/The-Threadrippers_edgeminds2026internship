// features/onboarding/services/onboarding_prefs.dart
// Purpose: Manages reading and writing local settings configuration to a JSON file (~/.kivo_workspace_config.json).

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants/app_constants.dart';

class OnboardingPrefs {
  static Future<Map<String, dynamic>> read() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.backendBaseUrl}/system/settings'),
      );
      if (response.statusCode == 200) {
        return json.decode(utf8.decoder.convert(response.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  static Future<void> write(Map<String, dynamic> data) async {
    try {
      await http.post(
        Uri.parse('${AppConstants.backendBaseUrl}/system/settings'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
    } catch (_) {}
  }

  // --- Convenience Getters ---
  static Future<bool> isOnboardingComplete() async {
    final data = await read();
    return data['onboardingCompleted'] as bool? ?? false;
  }

  static Future<bool> isTutorialComplete() async {
    final data = await read();
    return data['tutorialCompleted'] as bool? ?? false;
  }

  static Future<List<String>> getSelectedModels() async {
    final data = await read();
    final list = data['selectedModels'] as List<dynamic>?;
    return list?.map((e) => e.toString()).toList() ?? ['qwen2.5:1.5b'];
  }

  static Future<List<String>> getDownloadedModels() async {
    final data = await read();
    final list = data['downloadedModels'] as List<dynamic>?;
    return list?.map((e) => e.toString()).toList() ?? [];
  }

  static Future<String> getThemeMode() async {
    final data = await read();
    return data['themeMode'] as String? ?? 'light';
  }

  static Future<String> getFontFamily() async {
    final data = await read();
    return data['fontFamily'] as String? ?? 'sans';
  }

  static Future<String> getAccentColor() async {
    final data = await read();
    return data['accentColor'] as String? ?? '#0075DE';
  }

  static Future<String> getOllamaUrl() async {
    final data = await read();
    return data['ollamaUrl'] as String? ?? 'http://localhost:11434';
  }

  static Future<String> getActiveModel() async {
    final data = await read();
    return data['activeModel'] as String? ?? 'qwen2.5:1.5b';
  }
}
