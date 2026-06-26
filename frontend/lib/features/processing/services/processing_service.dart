// features/processing/services/processing_service.dart
// Purpose: API Service for starting, checking, and cancelling workspace processing queues.
// Responsibilities: Performs GET and POST requests for processing status.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../models/processing_status.dart';

final processingServiceProvider = Provider<ProcessingService>((ref) {
  return ProcessingService();
});

class ProcessingService {
  final http.Client _client;

  ProcessingService({http.Client? client}) : _client = client ?? http.Client();

  Future<ProcessingStatus> startProcessing(String workspaceId, {int? chunkSize, int? chunkOverlap}) async {
    var uri = Uri.parse('${AppConstants.backendBaseUrl}/workspaces/$workspaceId/processing/process');
    final queryParams = <String, String>{};
    if (chunkSize != null) queryParams['chunk_size'] = chunkSize.toString();
    if (chunkOverlap != null) queryParams['chunk_overlap'] = chunkOverlap.toString();
    if (queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams);
    }

    final response = await _client.post(uri);

    if (response.statusCode == 200) {
      return ProcessingStatus.fromJson(json.decode(utf8.decode(response.bodyBytes)));
    } else {
      final Map<String, dynamic> err = json.decode(response.body);
      throw Exception(err['detail'] ?? 'Failed to start processing');
    }
  }

  Future<ProcessingStatus> getProcessingStatus(String workspaceId) async {
    final response = await _client.get(
      Uri.parse('${AppConstants.backendBaseUrl}/workspaces/$workspaceId/processing/processing-status'),
    );

    if (response.statusCode == 200) {
      return ProcessingStatus.fromJson(json.decode(utf8.decode(response.bodyBytes)));
    } else {
      throw Exception('Failed to get processing status: Status ${response.statusCode}');
    }
  }

  Future<void> cancelProcessing(String workspaceId) async {
    final response = await _client.post(
      Uri.parse('${AppConstants.backendBaseUrl}/workspaces/$workspaceId/processing/cancel-processing'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to cancel processing: Status ${response.statusCode}');
    }
  }
}
