// features/chat/providers/chat_providers.dart
// Purpose: Riverpod state notifier to manage chat message list and loading/error states.
// Responsibilities: Exposes chat messages, appends new messages, and triggers API calls.

import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_message.dart';
import '../models/citation.dart';
import '../services/chat_service.dart';
import '../../../core/theme/theme_provider.dart';

class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final bool isStreaming;
  final String? errorMessage;

  ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isStreaming = false,
    this.errorMessage,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? isStreaming,
    String? errorMessage,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isStreaming: isStreaming ?? this.isStreaming,
      errorMessage: errorMessage,
    );
  }
}

class QueryRecord {
  final String workspaceId;
  final String question;
  final int latencyMs;
  final DateTime timestamp;

  QueryRecord({
    required this.workspaceId,
    required this.question,
    required this.latencyMs,
    required this.timestamp,
  });
}

class QueryHistoryNotifier extends StateNotifier<List<QueryRecord>> {
  QueryHistoryNotifier() : super([]);

  void addRecord(String workspaceId, String question, int latencyMs) {
    state = [
      ...state,
      QueryRecord(
        workspaceId: workspaceId,
        question: question,
        latencyMs: latencyMs,
        timestamp: DateTime.now(),
      ),
    ];
  }
}

final queryHistoryProvider = StateNotifierProvider<QueryHistoryNotifier, List<QueryRecord>>((ref) {
  return QueryHistoryNotifier();
});

class ChatNotifier extends StateNotifier<ChatState> {
  final ChatService _service;
  final String _workspaceId;
  final Ref _ref;
  StreamSubscription<String>? _subscription;
  Completer<void>? _completer;

  ChatNotifier(this._service, this._workspaceId, this._ref) : super(ChatState());

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void stopAddressing() {
    if (_subscription != null) {
      _subscription!.cancel();
      _subscription = null;
    }
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
    }
    state = state.copyWith(
      isLoading: false,
      isStreaming: false,
    );
  }

  Future<void> sendMessage(String text, {bool isStrict = true}) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return;

    if (state.isStreaming) return;

    final userMessage = ChatMessage(
      text: trimmedText,
      isUser: true,
      timestamp: DateTime.now(),
    );

    // 1. Append user message, set loading=true and isStreaming=true
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isLoading: true,
      isStreaming: true,
      errorMessage: null,
    );

    _completer = Completer<void>();

    try {
      // 2. Prepare blank assistant message placeholder
      var assistantMessage = ChatMessage(
        text: '',
        isUser: false,
        timestamp: DateTime.now(),
      );

      // Append placeholder
      state = state.copyWith(
        messages: [...state.messages, assistantMessage],
      );

      // 3. Connect to stream
      final temp = _ref.read(ragTemperatureProvider);
      final threshold = _ref.read(ragSimilarityThresholdProvider);
      final ollamaUrl = _ref.read(ollamaUrlProvider);
      final activeModel = _ref.read(activeModelProvider);

      final stream = _service.sendQueryStream(
        _workspaceId,
        trimmedText,
        isStrict: isStrict,
        temperature: temp,
        similarityThreshold: threshold,
        ollamaUrl: ollamaUrl,
        modelName: activeModel,
      );
      bool isFirstToken = true;

      _subscription = stream.listen(
        (event) {
          if (event.trim().isEmpty) return;
          final Map<String, dynamic> data = json.decode(event);

          if (data['done'] == true) {
            // Final chunk with full clean answer and citation metadata
            final citationsJson = data['citations'] as List<dynamic>? ?? [];
            final recQuestions = List<String>.from(data['recommended_questions'] as List<dynamic>? ?? []);
            final finalCitations = citationsJson.map((c) => Citation.fromJson(c)).toList();
            final finalAnswer = data['answer'] as String? ?? (data['token'] as String?) ?? assistantMessage.text;
            final latencyMs = data['latency_ms'] as int? ?? 0;
            _ref.read(queryHistoryProvider.notifier).addRecord(_workspaceId, trimmedText, latencyMs);

            state = state.copyWith(
              messages: [
                ...state.messages.sublist(0, state.messages.length - 1),
                assistantMessage.copyWith(
                  text: finalAnswer,
                  citations: finalCitations,
                  recommendedQuestions: recQuestions,
                ),
              ],
              isLoading: false,
              isStreaming: false,
            );
            if (_completer != null && !_completer!.isCompleted) {
              _completer!.complete();
            }
            _subscription = null;
          } else {
            // Regular token chunk
            final token = data['token'] as String? ?? '';
            
            assistantMessage = assistantMessage.copyWith(
              text: assistantMessage.text + token,
            );

            state = state.copyWith(
              messages: [
                ...state.messages.sublist(0, state.messages.length - 1),
                assistantMessage,
              ],
              // Set isLoading to false on first token to hide the skeleton loader
              isLoading: isFirstToken ? false : state.isLoading,
            );
            
            isFirstToken = false;
          }
        },
        onError: (e) {
          var currentMessages = state.messages;
          if (currentMessages.isNotEmpty && !currentMessages.last.isUser && currentMessages.last.text.isEmpty) {
            currentMessages = currentMessages.sublist(0, currentMessages.length - 1);
          }
          state = state.copyWith(
            messages: currentMessages,
            isLoading: false,
            isStreaming: false,
            errorMessage: e.toString().replaceAll('Exception: ', ''),
          );
          if (_completer != null && !_completer!.isCompleted) {
            _completer!.completeError(e);
          }
          _subscription = null;
        },
        onDone: () {
          state = state.copyWith(
            isLoading: false,
            isStreaming: false,
          );
          if (_completer != null && !_completer!.isCompleted) {
            _completer!.complete();
          }
          _subscription = null;
        },
        cancelOnError: true,
      );

      await _completer!.future;
    } catch (e) {
      var currentMessages = state.messages;
      if (currentMessages.isNotEmpty && !currentMessages.last.isUser && currentMessages.last.text.isEmpty) {
        currentMessages = currentMessages.sublist(0, currentMessages.length - 1);
      }
      state = state.copyWith(
        messages: currentMessages,
        isLoading: false,
        isStreaming: false,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  void clearChat() {
    state = ChatState(messages: const []);
  }
}

// family family allows us to instantiate a notifier per active workspace ID.
final chatProvider = StateNotifierProvider.family<ChatNotifier, ChatState, String>((ref, workspaceId) {
  final service = ref.watch(chatServiceProvider);
  return ChatNotifier(service, workspaceId, ref);
});

class UniversalChatNotifier extends StateNotifier<ChatState> {
  final ChatService _service;
  final Ref _ref;
  StreamSubscription<String>? _subscription;
  Completer<void>? _completer;

  UniversalChatNotifier(this._service, this._ref) : super(ChatState());

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void stopAddressing() {
    if (_subscription != null) {
      _subscription!.cancel();
      _subscription = null;
    }
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
    }
    state = state.copyWith(
      isLoading: false,
      isStreaming: false,
    );
  }

  Future<void> sendUniversalMessage(List<String> workspaceIds, String text, {bool isStrict = true}) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty || workspaceIds.isEmpty) return;

    if (state.isStreaming) return;

    final userMessage = ChatMessage(
      text: trimmedText,
      isUser: true,
      timestamp: DateTime.now(),
    );

    // Append user message, set loading=true and isStreaming=true
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isLoading: true,
      isStreaming: true,
      errorMessage: null,
    );

    _completer = Completer<void>();

    try {
      // Prepare assistant message placeholder
      var assistantMessage = ChatMessage(
        text: '',
        isUser: false,
        timestamp: DateTime.now(),
      );

      // Append placeholder
      state = state.copyWith(
        messages: [...state.messages, assistantMessage],
      );

      // Retrieve overriding parameters
      final temp = _ref.read(ragTemperatureProvider);
      final threshold = _ref.read(ragSimilarityThresholdProvider);
      final ollamaUrl = _ref.read(ollamaUrlProvider);
      final activeModel = _ref.read(activeModelProvider);

      final stream = _service.sendUniversalQueryStream(
        workspaceIds,
        trimmedText,
        isStrict: isStrict,
        temperature: temp,
        similarityThreshold: threshold,
        ollamaUrl: ollamaUrl,
        modelName: activeModel,
      );
      bool isFirstToken = true;

      _subscription = stream.listen(
        (event) {
          if (event.trim().isEmpty) return;
          final Map<String, dynamic> data = json.decode(event);

          if (data['done'] == true) {
            final citationsJson = data['citations'] as List<dynamic>? ?? [];
            final recQuestions = List<String>.from(data['recommended_questions'] as List<dynamic>? ?? []);
            final finalCitations = citationsJson.map((c) => Citation.fromJson(c)).toList();
            final finalAnswer = data['answer'] as String? ?? (data['token'] as String?) ?? assistantMessage.text;
            final latencyMs = data['latency_ms'] as int? ?? 0;
            _ref.read(queryHistoryProvider.notifier).addRecord('universal', trimmedText, latencyMs);

            state = state.copyWith(
              messages: [
                ...state.messages.sublist(0, state.messages.length - 1),
                assistantMessage.copyWith(
                  text: finalAnswer,
                  citations: finalCitations,
                  recommendedQuestions: recQuestions,
                ),
              ],
              isLoading: false,
              isStreaming: false,
            );
            if (_completer != null && !_completer!.isCompleted) {
              _completer!.complete();
            }
            _subscription = null;
          } else {
            final token = data['token'] as String? ?? '';
            
            assistantMessage = assistantMessage.copyWith(
              text: assistantMessage.text + token,
            );

            state = state.copyWith(
              messages: [
                ...state.messages.sublist(0, state.messages.length - 1),
                assistantMessage,
              ],
              isLoading: isFirstToken ? false : state.isLoading,
            );
            
            isFirstToken = false;
          }
        },
        onError: (e) {
          var currentMessages = state.messages;
          if (currentMessages.isNotEmpty && !currentMessages.last.isUser && currentMessages.last.text.isEmpty) {
            currentMessages = currentMessages.sublist(0, currentMessages.length - 1);
          }
          state = state.copyWith(
            messages: currentMessages,
            isLoading: false,
            isStreaming: false,
            errorMessage: e.toString().replaceAll('Exception: ', ''),
          );
          if (_completer != null && !_completer!.isCompleted) {
            _completer!.completeError(e);
          }
          _subscription = null;
        },
        onDone: () {
          state = state.copyWith(
            isLoading: false,
            isStreaming: false,
          );
          if (_completer != null && !_completer!.isCompleted) {
            _completer!.complete();
          }
          _subscription = null;
        },
        cancelOnError: true,
      );

      await _completer!.future;
    } catch (e) {
      var currentMessages = state.messages;
      if (currentMessages.isNotEmpty && !currentMessages.last.isUser && currentMessages.last.text.isEmpty) {
        currentMessages = currentMessages.sublist(0, currentMessages.length - 1);
      }
      state = state.copyWith(
        messages: currentMessages,
        isLoading: false,
        isStreaming: false,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  void clearChat() {
    state = ChatState(messages: const []);
  }
}

final universalChatProvider = StateNotifierProvider<UniversalChatNotifier, ChatState>((ref) {
  final service = ref.watch(chatServiceProvider);
  return UniversalChatNotifier(service, ref);
});

