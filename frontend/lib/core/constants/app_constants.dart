// app/core/constants/app_constants.dart
// Purpose: Application-wide constants for Kivo Workspace.
// Responsibilities: Defines app name, version, backend URL.

import 'package:flutter/foundation.dart';

class AppConstants {
  AppConstants._();

  static const String appName = 'Kivo Workspace';
  static const String appVersion = '1.1.0';

  static String _backendBaseUrl = 'http://127.0.0.1:8000';

  // Backend base URL — FastAPI running locally (can be updated dynamically if port 8000 is in use)
  static String get backendBaseUrl {
    if (kIsWeb) {
      if (kReleaseMode) {
        final uri = Uri.base;
        return '${uri.scheme}://${uri.host}:${uri.port}';
      } else {
        // Local web development (Chrome dev server port != backend port)
        return 'http://127.0.0.1:8000';
      }
    }
    return _backendBaseUrl;
  }

  static set backendBaseUrl(String url) {
    _backendBaseUrl = url;
  }

  // API endpoints
  static const String healthEndpoint = '/health';
  static const String workspacesEndpoint = '/workspaces';
}
