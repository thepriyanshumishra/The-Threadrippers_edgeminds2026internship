import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

final accentColorProvider = StateProvider<Color>((ref) => const Color(0xFF0075DE));

final notificationsEnabledProvider = StateProvider<bool>((ref) => true);

final ollamaUrlProvider = StateProvider<String>((ref) => 'http://localhost:11434');

final ragTemperatureProvider = StateProvider<double>((ref) => 0.0);

final ragSimilarityThresholdProvider = StateProvider<double>((ref) => 0.35);

final ragChunkSizeProvider = StateProvider<int>((ref) => 750);

final ragChunkOverlapProvider = StateProvider<int>((ref) => 150);

final activeModelProvider = StateProvider<String>((ref) => 'qwen2.5:1.5b');
