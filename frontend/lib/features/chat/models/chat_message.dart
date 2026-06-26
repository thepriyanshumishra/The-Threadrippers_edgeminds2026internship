// features/chat/models/chat_message.dart
// Purpose: Class representing a single chat message in the UI thread.
// Responsibilities: Stores text, role, citations, and timestamp.

import 'citation.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final List<Citation> citations;
  final List<String> recommendedQuestions;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.citations = const [],
    this.recommendedQuestions = const [],
  });

  ChatMessage copyWith({
    String? text,
    bool? isUser,
    DateTime? timestamp,
    List<Citation>? citations,
    List<String>? recommendedQuestions,
  }) {
    return ChatMessage(
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      citations: citations ?? this.citations,
      recommendedQuestions: recommendedQuestions ?? this.recommendedQuestions,
    );
  }
}
