// features/processing/services/system_health_service.dart
// Purpose: API Service for retrieving system diagnostics from the backend.
// Responsibilities: Performs GET request to fetch real-time system health data.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../models/system_diagnostics.dart';

final systemHealthServiceProvider = Provider<SystemHealthService>((ref) {
  return SystemHealthService();
});

final systemDiagnosticsProvider = FutureProvider.autoDispose<SystemDiagnostics>((ref) async {
  final service = ref.watch(systemHealthServiceProvider);
  return service.getDiagnostics();
});

class SystemHealthService {
  final http.Client _client;

  SystemHealthService({http.Client? client}) : _client = client ?? http.Client();

  Future<SystemDiagnostics> getDiagnostics() async {
    final response = await _client.get(
      Uri.parse('${AppConstants.backendBaseUrl}/system/diagnostics'),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      return SystemDiagnostics.fromJson(data);
    } else {
      throw Exception('Failed to load system diagnostics: Status ${response.statusCode}');
    }
  }
}
