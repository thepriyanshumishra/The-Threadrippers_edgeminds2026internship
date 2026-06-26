// features/source_upload/services/source_service.dart
// Purpose: API Service for uploading files and adding YouTube URLs to workspaces.
// Responsibilities: Performs GET, POST (multipart & JSON), and DELETE requests for sources.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../models/source.dart';

final sourceServiceProvider = Provider<SourceService>((ref) {
  return SourceService();
});

class SourceService {
  final http.Client _client;

  SourceService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<Source>> getSources(String workspaceId) async {
    final response = await _client.get(
      Uri.parse('${AppConstants.backendBaseUrl}/workspaces/$workspaceId/sources'),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      return data.map((item) => Source.fromJson(item)).toList();
    } else {
      throw Exception('Failed to load workspace sources: Status ${response.statusCode}');
    }
  }

  Future<List<Source>> uploadFile(String workspaceId, List<int> bytes, String fileName) async {
    final uri = Uri.parse('${AppConstants.backendBaseUrl}/workspaces/$workspaceId/sources/upload');
    final request = http.MultipartRequest('POST', uri);

    request.files.add(
      http.MultipartFile.fromBytes(
        'files',
        bytes,
        filename: fileName,
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      return data.map((item) => Source.fromJson(item)).toList();
    } else {
      final Map<String, dynamic> err = json.decode(response.body);
      throw Exception(err['detail'] ?? 'Failed to upload source file');
    }
  }

  Future<Source> addYouTubeUrl(String workspaceId, String url) async {
    final response = await _client.post(
      Uri.parse('${AppConstants.backendBaseUrl}/workspaces/$workspaceId/sources/youtube'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'url': url}),
    );

    if (response.statusCode == 200) {
      return Source.fromJson(json.decode(utf8.decode(response.bodyBytes)));
    } else {
      final Map<String, dynamic> err = json.decode(response.body);
      throw Exception(err['detail'] ?? 'Failed to register YouTube URL');
    }
  }

  Future<void> deleteSource(String workspaceId, String sourceId) async {
    final response = await _client.delete(
      Uri.parse('${AppConstants.backendBaseUrl}/workspaces/$workspaceId/sources/$sourceId'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete source: Status ${response.statusCode}');
    }
  }

  Future<Source> addWebsiteUrl(String workspaceId, String url) async {
    final response = await _client.post(
      Uri.parse('${AppConstants.backendBaseUrl}/workspaces/$workspaceId/sources/website'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'url': url}),
    );

    if (response.statusCode == 200) {
      return Source.fromJson(json.decode(utf8.decode(response.bodyBytes)));
    } else {
      final Map<String, dynamic> err = json.decode(response.body);
      throw Exception(err['detail'] ?? 'Failed to register Website URL');
    }
  }

  Future<Source> addCopiedText(String workspaceId, String title, String content) async {
    final response = await _client.post(
      Uri.parse('${AppConstants.backendBaseUrl}/workspaces/$workspaceId/sources/text'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': title, 'content': content}),
    );

    if (response.statusCode == 200) {
      return Source.fromJson(json.decode(utf8.decode(response.bodyBytes)));
    } else {
      final Map<String, dynamic> err = json.decode(response.body);
      throw Exception(err['detail'] ?? 'Failed to save copied text');
    }
  }

  Future<Source> addCopiedEmail(String workspaceId, String subject, String sender, String recipient, String body) async {
    final response = await _client.post(
      Uri.parse('${AppConstants.backendBaseUrl}/workspaces/$workspaceId/sources/email'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'subject': subject,
        'sender': sender,
        'recipient': recipient,
        'body': body,
      }),
    );

    if (response.statusCode == 200) {
      return Source.fromJson(json.decode(utf8.decode(response.bodyBytes)));
    } else {
      final Map<String, dynamic> err = json.decode(response.body);
      throw Exception(err['detail'] ?? 'Failed to save copied email');
    }
  }
}
