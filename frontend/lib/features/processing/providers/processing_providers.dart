// features/processing/providers/processing_providers.dart
// Purpose: Stream provider for polling workspace processing progress status.
// Responsibilities: Yields updates every 1.5 seconds while status is 'processing'.

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/processing_status.dart';
import '../services/processing_service.dart';

final processingStatusProvider = StreamProvider.family.autoDispose<ProcessingStatus, String>((ref, workspaceId) async* {
  final service = ref.watch(processingServiceProvider);

  // Initial immediate fetch
  final initialStatus = await service.getProcessingStatus(workspaceId);
  yield initialStatus;

  // Stop polling if job is already terminated (ready, failed, or cancelled)
  if (!initialStatus.isProcessing) {
    return;
  }

  // Set up periodic polling stream
  final controller = StreamController<ProcessingStatus>();
  final timer = Timer.periodic(const Duration(milliseconds: 1500), (t) async {
    try {
      final status = await service.getProcessingStatus(workspaceId);
      if (controller.isClosed) return;
      controller.add(status);
      if (!status.isProcessing) {
        t.cancel();
        controller.close();
      }
    } catch (e, stack) {
      if (!controller.isClosed) {
        controller.addError(e, stack);
      }
      t.cancel();
    }
  });

  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });

  yield* controller.stream;
});
