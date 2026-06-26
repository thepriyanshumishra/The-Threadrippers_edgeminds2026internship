// test/processing_test.dart
// Purpose: Unit tests for ProcessingStatus model.
// Responsibilities: Verifies JSON deserialization and utility helper states.

import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_workspace/features/processing/models/processing_status.dart';

void main() {
  group('ProcessingStatus Model Tests', () {
    test('JSON deserialization works correctly', () {
      final json = {
        'status': 'processing',
        'current_step': 'pdf_extraction',
        'progress': 0.33,
        'steps': ['pdf_extraction', 'embedding_generation', 'building_knowledge_base'],
        'completed_steps': [],
      };

      final status = ProcessingStatus.fromJson(json);

      expect(status.status, 'processing');
      expect(status.currentStep, 'pdf_extraction');
      expect(status.progress, 0.33);
      expect(status.steps, ['pdf_extraction', 'embedding_generation', 'building_knowledge_base']);
      expect(status.completedSteps, isEmpty);
      expect(status.isProcessing, true);
      expect(status.isReady, false);
    });

    test('Status helpers work correctly for ready status', () {
      final json = {
        'status': 'ready',
        'current_step': null,
        'progress': 1.0,
        'steps': ['pdf_extraction', 'embedding_generation', 'building_knowledge_base'],
        'completed_steps': ['pdf_extraction', 'embedding_generation', 'building_knowledge_base'],
      };

      final status = ProcessingStatus.fromJson(json);

      expect(status.status, 'ready');
      expect(status.isProcessing, false);
      expect(status.isReady, true);
      expect(status.isCancelled, false);
      expect(status.isFailed, false);
    });
  });
}
