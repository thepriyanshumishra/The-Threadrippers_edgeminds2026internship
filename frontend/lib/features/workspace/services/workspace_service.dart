// features/workspace/services/workspace_service.dart
// Purpose: API Service for communicating with FastAPI workspace endpoints.
// Responsibilities: Performs GET, POST, PUT, DELETE requests for workspaces.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../models/workspace.dart';

final workspaceServiceProvider = Provider<WorkspaceService>((ref) {
  return WorkspaceService();
});

class WorkspaceService {
  final http.Client _client;

  WorkspaceService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<Workspace>> getWorkspaces() async {
    final response = await _client.get(
      Uri.parse('${AppConstants.backendBaseUrl}${AppConstants.workspacesEndpoint}'),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      return data.map((item) => Workspace.fromJson(item)).toList();
    } else {
      throw Exception('Failed to load workspaces from backend: Status ${response.statusCode}');
    }
  }

  Future<Workspace> getWorkspace(String id) async {
    final response = await _client.get(
      Uri.parse('${AppConstants.backendBaseUrl}${AppConstants.workspacesEndpoint}/$id'),
    );

    if (response.statusCode == 200) {
      return Workspace.fromJson(json.decode(utf8.decode(response.bodyBytes)));
    } else {
      throw Exception('Failed to load workspace details: Status ${response.statusCode}');
    }
  }

  Future<Workspace> createWorkspace(String name) async {
    final response = await _client.post(
      Uri.parse('${AppConstants.backendBaseUrl}${AppConstants.workspacesEndpoint}'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': name}),
    );

    if (response.statusCode == 200) {
      return Workspace.fromJson(json.decode(utf8.decode(response.bodyBytes)));
    } else {
      throw Exception('Failed to create workspace: Status ${response.statusCode}');
    }
  }

  Future<Workspace> renameWorkspace(String id, String name) async {
    final response = await _client.put(
      Uri.parse('${AppConstants.backendBaseUrl}${AppConstants.workspacesEndpoint}/$id'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': name}),
    );

    if (response.statusCode == 200) {
      return Workspace.fromJson(json.decode(utf8.decode(response.bodyBytes)));
    } else {
      throw Exception('Failed to rename workspace: Status ${response.statusCode}');
    }
  }

  Future<Workspace> updateWorkspace(String id, {String? name, String? instructions}) async {
    final Map<String, dynamic> body = {};
    if (name != null) body['name'] = name;
    if (instructions != null) body['instructions'] = instructions;

    final response = await _client.put(
      Uri.parse('${AppConstants.backendBaseUrl}${AppConstants.workspacesEndpoint}/$id'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      return Workspace.fromJson(json.decode(utf8.decode(response.bodyBytes)));
    } else {
      throw Exception('Failed to update workspace settings: Status ${response.statusCode}');
    }
  }

  Future<void> deleteWorkspace(String id) async {
    final response = await _client.delete(
      Uri.parse('${AppConstants.backendBaseUrl}${AppConstants.workspacesEndpoint}/$id'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete workspace: Status ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getWorkspaceStats(String id) async {
    final response = await _client.get(
      Uri.parse('${AppConstants.backendBaseUrl}${AppConstants.workspacesEndpoint}/$id/stats'),
    );

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(json.decode(utf8.decode(response.bodyBytes)));
    } else {
      throw Exception('Failed to load workspace stats: Status ${response.statusCode}');
    }
  }
}
// 
