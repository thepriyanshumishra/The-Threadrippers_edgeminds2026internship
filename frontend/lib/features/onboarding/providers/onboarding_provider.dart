// features/onboarding/providers/onboarding_provider.dart
// Purpose: Riverpod state notifier managing the 6 onboarding stages and model downloads.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/onboarding_state.dart';
import '../services/onboarding_service.dart';
import '../services/onboarding_prefs.dart';

final onboardingServiceProvider = Provider<OnboardingService>((ref) => OnboardingService());

final onboardingProvider = StateNotifierProvider<OnboardingNotifier, OnboardingProgress>((ref) {
  final service = ref.watch(onboardingServiceProvider);
  return OnboardingNotifier(service);
});

class OnboardingNotifier extends StateNotifier<OnboardingProgress> {
  final OnboardingService _service;
  Timer? _downloadTimer;
  StreamSubscription<double>? _pullSub;
  Timer? _connTimer;

  // Sliding window for accurate ETA (last 8 speed samples)
  final List<double> _speedSamples = [];
  static const int _speedWindowSize = 8;

  OnboardingNotifier(this._service) : super(OnboardingProgress()) {
    refreshOllamaStatus();
  }

  /// Check Ollama status and fetch dependencies/installed models.
  Future<void> refreshOllamaStatus() async {
    try {
      // Proactively start the local Ollama service if it is installed (desktop only)
      if (!kIsWeb && _service.lookupOllamaBinary()) {
        await _service.startOllamaService();
        // Give it a brief moment to bind to the port
        await Future.delayed(const Duration(milliseconds: 1200));
      }

      final deps = await _service.checkDependencies();
      state = state.copyWith(
        isOllamaInstalled: deps['ollamaInstalled'] ?? false,
        installedOllamaModels: List<String>.from(deps['ollamaModels'] ?? []),
        isInternetConnected: await _service.checkInternetConnection(),
      );
    } catch (e, stack) {
      debugPrint("Error in refreshOllamaStatus: $e\n$stack");
    }
  }

  /// Delete a model from local Ollama and refresh status.
  Future<void> deleteInstalledModel(String modelId) async {
    try {
      await _service.deleteOllamaModel(modelId);
      final current = List<String>.from(state.selectedModelIds);
      if (current.contains(modelId)) {
        current.remove(modelId);
      }
      state = state.copyWith(selectedModelIds: current);
      await refreshOllamaStatus();
    } catch (e) {
      debugPrint("Failed to delete model: $e");
    }
  }

  void nextStage() {
    final currentIdx = state.activeStage.index;
    if (currentIdx < OnboardingStage.values.length - 1) {
      final nextStage = OnboardingStage.values[currentIdx + 1];
      state = state.copyWith(activeStage: nextStage);

      // Trigger automatic operations when entering downloading stage
      if (nextStage == OnboardingStage.downloading) {
        startDownloading();
      }
    }
  }

  void prevStage() {
    final currentIdx = state.activeStage.index;
    if (currentIdx > 0) {
      // Don't go back from customization into downloading if it is actively running
      if (state.activeStage == OnboardingStage.customization &&
          state.isDownloading &&
          state.downloadProgress > 0 &&
          state.downloadProgress < 1.0) {
        return;
      }
      state = state.copyWith(activeStage: OnboardingStage.values[currentIdx - 1]);
    }
  }

  void toggleModelSelection(String modelId) {
    final current = List<String>.from(state.selectedModelIds);
    if (current.contains(modelId)) {
      if (current.length > 1) current.remove(modelId);
    } else {
      current.add(modelId);
    }
    state = state.copyWith(selectedModelIds: current);
  }

  /// Total model download size only (Ollama skip if already installed).
  double getCalculatedDownloadSize() {
    double total = 0.0;
    if (!state.isOllamaInstalled) total += 0.30; // 300 MB bundled Ollama

    for (final id in state.selectedModelIds) {
      final isAlreadyInstalled = state.installedOllamaModels.any(
        (m) => m == id || m.startsWith('$id:') || id.startsWith('$m:'),
      );
      if (!isAlreadyInstalled) {
        final match = curatedModelRegistry.firstWhere(
          (m) => m.id == id,
          orElse: () => curatedModelRegistry[0],
        );
        total += match.sizeGb;
      }
    }
    return double.parse(total.toStringAsFixed(2));
  }

  /// Cancel active download
  void cancelDownload() {
    _pullSub?.cancel();
    _pullSub = null;
    _connTimer?.cancel();
    _connTimer = null;
    _downloadTimer?.cancel();
    _downloadTimer = null;

    state = state.copyWith(
      isDownloading: false,
      downloadCancelled: true,
      downloadSpeed: 0.0,
    );
  }

  void cancelDownloadDueToNetworkLoss() {
    _pullSub?.cancel();
    _pullSub = null;
    _connTimer?.cancel();
    _connTimer = null;
    _downloadTimer?.cancel();
    _downloadTimer = null;

    state = state.copyWith(
      isDownloading: false,
      isInternetConnected: false,
      downloadSpeed: 0.0,
      errorMessage: 'Internet connection lost. Please check your network and retry.',
    );
  }

  /// Real Ollama pull with accurate speed-based ETA using a sliding window average.
  Future<void> startDownloading() async {
    _downloadTimer?.cancel();
    _pullSub?.cancel();
    _pullSub = null;
    _connTimer?.cancel();
    _connTimer = null;
    _speedSamples.clear();

    // Clear any previous error message and reset flags
    state = state.copyWith(
      errorMessage: null,
      isDownloading: true,
      downloadCancelled: false,
    );

    // Internet check first
    final isOnline = await _service.checkInternetConnection();
    if (!isOnline) {
      state = state.copyWith(
        isInternetConnected: false,
        isDownloading: false,
      );
      return;
    }

    // Ensure Ollama service is running
    await _service.startOllamaService();

    // Refresh Ollama status first to get the most accurate installed model list
    await refreshOllamaStatus();

    // Build the status map for all selected models
    final statusMap = <String, String>{};
    for (final id in state.selectedModelIds) {
      final isAlreadyInstalled = state.installedOllamaModels.any(
        (m) => m == id || m.startsWith('$id:') || id.startsWith('$m:'),
      );
      if (isAlreadyInstalled) {
        statusMap[id] = 'Installed ✅';
      } else {
        statusMap[id] = 'Pending';
      }
    }
    state = state.copyWith(installStatus: Map.from(statusMap));

    // Build list of models to pull (skip already installed)
    final modelsToPull = state.selectedModelIds.where((id) {
      return !state.installedOllamaModels.any(
        (m) => m == id || m.startsWith('$id:') || id.startsWith('$m:'),
      );
    }).toList();

    // Compute total MB upfront for progress bar
    double totalMb = state.isOllamaInstalled ? 0 : 300;
    for (final id in modelsToPull) {
      final match = curatedModelRegistry.firstWhere(
        (m) => m.id == id,
        orElse: () => curatedModelRegistry[0],
      );
      totalMb += match.sizeGb * 1024;
    }

    if (totalMb <= 0) {
      // Nothing to download — skip directly to customization
      state = state.copyWith(
        downloadProgress: 1.0,
        downloadedMb: 0,
        totalMb: 0,
        downloadEta: '0s',
        isDownloading: false,
      );
      nextStage();
      return;
    }

    final bool isResuming = state.downloadProgress > 0.0 && state.downloadProgress < 1.0;

    state = state.copyWith(
      totalMb: totalMb,
      downloadedMb: isResuming ? state.downloadedMb : 0.0,
      downloadProgress: isResuming ? state.downloadProgress : 0.0,
      downloadSpeed: 0.0,
      downloadEta: isResuming ? 'Resuming...' : 'Calculating...',
    );

    // Track time of last progress update to detect stalls
    DateTime lastProgressTime = DateTime.now();

    // Start periodic connection monitor with stall detection
    _connTimer = Timer.periodic(const Duration(milliseconds: 2500), (timer) async {
      final now = DateTime.now();
      final diff = now.difference(lastProgressTime).inMilliseconds;
      
      if (state.isDownloading && mounted) {
        if (diff >= 7500) {
          // If stalled for more than 7.5 seconds, display a warning in the ETA field
          state = state.copyWith(
            downloadEta: 'Stalled (Check connection or click Cancel to retry)',
            downloadSpeed: 0.0,
          );
        }
        
        if (diff >= 12000) {
          // If stalled for 12 seconds, check connectivity proactively
          final online = await _service.checkInternetConnection();
          if (!online && mounted) {
            cancelDownloadDueToNetworkLoss();
          }
        }
      }
    });

    // Pull models sequentially, updating progress as bytes arrive
    double cumulativeMb = 0.0;
    DateTime? lastSampleTime;
    double lastSampleBytes = 0.0;

    for (final modelId in modelsToPull) {
      if (state.downloadCancelled || !state.isDownloading) break;

      final match = curatedModelRegistry.firstWhere(
        (m) => m.id == modelId,
        orElse: () => curatedModelRegistry[0],
      );
      final modelMb = match.sizeGb * 1024;

      statusMap[modelId] = 'Downloading 0%';
      state = state.copyWith(installStatus: Map.from(statusMap));

      try {
        final completer = Completer<void>();
        final stream = _service.pullOllamaModel(modelId);

        _pullSub = stream.listen(
          (progressFraction) {
            if (!mounted || state.downloadCancelled || !state.isDownloading) {
              _pullSub?.cancel();
              if (!completer.isCompleted) completer.complete();
              return;
            }

            final now = DateTime.now();
            lastProgressTime = now;
            final downloadedThisModel = progressFraction * modelMb;
            final totalDownloaded = cumulativeMb + downloadedThisModel;

            // Speed calculation using sliding window
            if (lastSampleTime != null) {
              final elapsed = now.difference(lastSampleTime!).inMilliseconds / 1000.0;
              if (elapsed > 0.3) {
                final bytesDelta = totalDownloaded - lastSampleBytes;
                final instantSpeed = bytesDelta / elapsed; // MB/s
                _speedSamples.add(instantSpeed);
                if (_speedSamples.length > _speedWindowSize) _speedSamples.removeAt(0);
                lastSampleTime = now;
                lastSampleBytes = totalDownloaded;
              }
            } else {
              lastSampleTime = now;
              lastSampleBytes = totalDownloaded;
            }

            final avgSpeed = _speedSamples.isEmpty
                ? 0.0
                : _speedSamples.reduce((a, b) => a + b) / _speedSamples.length;

            final remainingMb = totalMb - totalDownloaded;
            final eta = _formatEta(avgSpeed > 0 ? (remainingMb / avgSpeed).round() : 0);

            final overallProgress = totalMb > 0 ? (totalDownloaded / totalMb).clamp(0.0, 1.0) : 0.0;

            statusMap[modelId] = 'Downloading ${(progressFraction * 100).toStringAsFixed(0)}%';
            state = state.copyWith(
              downloadedMb: double.parse(totalDownloaded.toStringAsFixed(1)),
              downloadProgress: overallProgress,
              downloadSpeed: double.parse(avgSpeed.toStringAsFixed(1)),
              downloadEta: eta,
              installStatus: Map.from(statusMap),
            );
          },
          onError: (err) {
            if (!completer.isCompleted) completer.completeError(err);
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );

        await completer.future;

        if (state.downloadCancelled || !state.isDownloading) {
          return;
        }

        // Verify if model is actually installed
        await refreshOllamaStatus();
        final isActuallyInstalled = state.installedOllamaModels.any(
          (m) => m == modelId || m.startsWith('$modelId:') || modelId.startsWith('$m:'),
        );
        if (!isActuallyInstalled) {
          throw Exception("Model pull completed but model not found in installed list");
        }

        cumulativeMb += modelMb;
        statusMap[modelId] = 'Ready ✅';
        state = state.copyWith(installStatus: Map.from(statusMap));
      } catch (e) {
        debugPrint("Error pulling model $modelId: $e");
        if (state.downloadCancelled) return;
        statusMap[modelId] = 'Failed ❌';
        state = state.copyWith(
          isDownloading: false,
          installStatus: Map.from(statusMap),
          errorMessage: 'Failed to download ${match.name}. Please ensure Ollama is running and try again.',
        );
        return; // Stop the flow
      }
    }

    _connTimer?.cancel();
    _connTimer = null;

    if (state.downloadCancelled || !state.isDownloading) return;

    // Finalize
    state = state.copyWith(
      downloadProgress: 1.0,
      downloadedMb: totalMb,
      downloadEta: '0s',
      downloadSpeed: 0,
      isDownloading: false,
    );

    await Future.delayed(const Duration(milliseconds: 600));
    nextStage(); // → customization
  }

  /// Simulated pull fallback for when Ollama is not reachable.
  Future<void> _simulatedPull(
    String modelId,
    double modelMb,
    double cumulativeBase,
    double totalMb,
    Map<String, String> statusMap,
  ) async {
    double simProgress = 0.0;
    while (simProgress < 1.0) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      if (state.downloadCancelled || !state.isDownloading) return;
      simProgress = (simProgress + 0.08).clamp(0.0, 1.0);
      final totalDone = cumulativeBase + simProgress * modelMb;
      final overall = totalMb > 0 ? (totalDone / totalMb).clamp(0.0, 1.0) : 0.0;
      final simSpeed = 6.0 + (simProgress * 4.0); // ramp up
      final eta = _formatEta(simSpeed > 0 ? ((totalMb - totalDone) / simSpeed).round() : 0);
      statusMap[modelId] = 'Downloading ${(simProgress * 100).toStringAsFixed(0)}%';
      state = state.copyWith(
        downloadedMb: double.parse(totalDone.toStringAsFixed(1)),
        downloadProgress: overall,
        downloadSpeed: double.parse(simSpeed.toStringAsFixed(1)),
        downloadEta: eta,
        installStatus: Map.from(statusMap),
      );
    }
  }

  String _formatEta(int totalSeconds) {
    if (totalSeconds <= 0) return '0s';
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  /// Retry download after reconnecting.
  Future<void> retryDownload() async {
    final connected = await _service.checkInternetConnection();
    if (connected) {
      state = state.copyWith(isInternetConnected: true);
      startDownloading();
    }
  }

  /// Save appearance + finalize onboarding.
  Future<void> completeOnboarding({
    required ThemeMode theme,
    required String font,
    required String accentHex,
  }) async {
    final downloaded = List<String>.from(state.selectedModelIds);

    await OnboardingPrefs.write({
      'onboardingCompleted': true,
      'themeMode': theme == ThemeMode.light ? 'light' : 'dark',
      'fontFamily': font,
      'accentColor': accentHex,
      'selectedModels': state.selectedModelIds,
      'downloadedModels': downloaded,
      'activeModel': state.selectedModelIds.first,
    });

    nextStage(); // → done
  }

  @override
  void dispose() {
    _downloadTimer?.cancel();
    _pullSub?.cancel();
    _connTimer?.cancel();
    super.dispose();
  }
}
