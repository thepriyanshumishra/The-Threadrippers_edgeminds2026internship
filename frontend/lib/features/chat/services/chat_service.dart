// features/chat/services/chat_service.dart
// Purpose: API Service for workspace chat communication.
// Responsibilities: Performs POST request to /workspaces/{id}/chat endpoint.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../models/citation.dart';

final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService();
});

class ChatResponseDto {
  final String answer;
  final String plainAnswer;
  final List<Citation> citations;
  final int latencyMs;
  final List<String> recommendedQuestions;

  ChatResponseDto({
    required this.answer,
    required this.plainAnswer,
    required this.citations,
    required this.latencyMs,
    required this.recommendedQuestions,
  });

  factory ChatResponseDto.fromJson(Map<String, dynamic> json) {
    final List<dynamic> citationList = json['citations'] as List<dynamic>? ?? [];
    final List<dynamic> recommendedList = json['recommended_questions'] as List<dynamic>? ?? [];
    return ChatResponseDto(
      answer: json['answer'] as String,
      plainAnswer: json['plain_answer'] as String? ?? json['answer'] as String,
      citations: citationList.map((c) => Citation.fromJson(c)).toList(),
      latencyMs: json['latency_ms'] as int? ?? 0,
      recommendedQuestions: List<String>.from(recommendedList),
    );
  }
}

class ChatService {
  final http.Client _client;

  ChatService({http.Client? client}) : _client = client ?? http.Client();

  Future<ChatResponseDto> sendQuery(
    String workspaceId,
    String question, {
    bool isStrict = true,
    double? temperature,
    double? similarityThreshold,
    String? ollamaUrl,
    String? modelName,
  }) async {
    final Map<String, dynamic> bodyMap = {
      'message': question,
      'is_strict': isStrict,
    };
    if (temperature != null) bodyMap['temperature'] = temperature;
    if (similarityThreshold != null) bodyMap['similarity_threshold'] = similarityThreshold;
    if (ollamaUrl != null && ollamaUrl.isNotEmpty) bodyMap['ollama_url'] = ollamaUrl;
    if (modelName != null && modelName.isNotEmpty) bodyMap['model_name'] = modelName;

    final response = await _client.post(
      Uri.parse('${AppConstants.backendBaseUrl}/workspaces/$workspaceId/chat'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(bodyMap),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      return ChatResponseDto.fromJson(data);
    } else {
      String errorMessage = 'Failed to get answer';
      try {
        final Map<String, dynamic> errData = json.decode(utf8.decode(response.bodyBytes));
        errorMessage = errData['detail'] ?? errorMessage;
      } catch (_) {}
      throw Exception('$errorMessage (Status ${response.statusCode})');
    }
  }

  Stream<String> sendQueryStream(
    String workspaceId,
    String question, {
    bool isStrict = true,
    double? temperature,
    double? similarityThreshold,
    String? ollamaUrl,
    String? modelName,
  }) async* {
    final request = http.Request(
      'POST',
      Uri.parse('${AppConstants.backendBaseUrl}/workspaces/$workspaceId/chat/stream'),
    );
    request.headers['Content-Type'] = 'application/json';
    
    final Map<String, dynamic> bodyMap = {
      'message': question,
      'is_strict': isStrict,
    };
    if (temperature != null) bodyMap['temperature'] = temperature;
    if (similarityThreshold != null) bodyMap['similarity_threshold'] = similarityThreshold;
    if (ollamaUrl != null && ollamaUrl.isNotEmpty) bodyMap['ollama_url'] = ollamaUrl;
    if (modelName != null && modelName.isNotEmpty) bodyMap['model_name'] = modelName;
    
    request.body = json.encode(bodyMap);

    final response = await _client.send(request);

    if (response.statusCode == 200) {
      final stream = response.stream.transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in stream) {
        if (line.startsWith('data: ')) {
          yield line.substring(6);
        }
      }
    } else {
      throw Exception('Streaming query failed (Status ${response.statusCode})');
    }
  }

  Future<ChatResponseDto> sendUniversalQuery(
    List<String> workspaceIds,
    String question, {
    bool isStrict = true,
    double? temperature,
    double? similarityThreshold,
    String? ollamaUrl,
    String? modelName,
  }) async {
    final Map<String, dynamic> bodyMap = {
      'message': question,
      'workspace_ids': workspaceIds,
      'is_strict': isStrict,
    };
    if (temperature != null) bodyMap['temperature'] = temperature;
    if (similarityThreshold != null) bodyMap['similarity_threshold'] = similarityThreshold;
    if (ollamaUrl != null && ollamaUrl.isNotEmpty) bodyMap['ollama_url'] = ollamaUrl;
    if (modelName != null && modelName.isNotEmpty) bodyMap['model_name'] = modelName;

    final response = await _client.post(
      Uri.parse('${AppConstants.backendBaseUrl}/universal-chat'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(bodyMap),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      return ChatResponseDto.fromJson(data);
    } else {
      String errorMessage = 'Failed to get answer';
      try {
        final Map<String, dynamic> errData = json.decode(utf8.decode(response.bodyBytes));
        errorMessage = errData['detail'] ?? errorMessage;
      } catch (_) {}
      throw Exception('$errorMessage (Status ${response.statusCode})');
    }
  }

  Stream<String> sendUniversalQueryStream(
    List<String> workspaceIds,
    String question, {
    bool isStrict = true,
    double? temperature,
    double? similarityThreshold,
    String? ollamaUrl,
    String? modelName,
  }) async* {
    final request = http.Request(
      'POST',
      Uri.parse('${AppConstants.backendBaseUrl}/universal-chat/stream'),
    );
    request.headers['Content-Type'] = 'application/json';
    
    final Map<String, dynamic> bodyMap = {
      'message': question,
      'workspace_ids': workspaceIds,
      'is_strict': isStrict,
    };
    if (temperature != null) bodyMap['temperature'] = temperature;
    if (similarityThreshold != null) bodyMap['similarity_threshold'] = similarityThreshold;
    if (ollamaUrl != null && ollamaUrl.isNotEmpty) bodyMap['ollama_url'] = ollamaUrl;
    if (modelName != null && modelName.isNotEmpty) bodyMap['model_name'] = modelName;
    
    request.body = json.encode(bodyMap);

    final response = await _client.send(request);

    if (response.statusCode == 200) {
      final stream = response.stream.transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in stream) {
        if (line.startsWith('data: ')) {
          yield line.substring(6);
        }
      }
    } else {
      throw Exception('Streaming universal query failed (Status ${response.statusCode})');
    }
  }
}

