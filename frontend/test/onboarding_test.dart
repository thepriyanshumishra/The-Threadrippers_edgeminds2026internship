import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_workspace/features/onboarding/models/onboarding_state.dart';
import 'package:kivo_workspace/features/onboarding/providers/onboarding_provider.dart';
import 'package:kivo_workspace/features/onboarding/services/onboarding_service.dart';

class MockOnboardingService extends OnboardingService {
  @override
  Future<Map<String, String>> checkSystemSpecs() async {
    return {
      'os': 'macos',
      'cores': '8',
      'arch': 'arm64',
      'ram': '16.0 GB',
    };
  }

  @override
  Future<bool> checkInternetConnection() async {
    return true;
  }

  @override
  Future<Map<String, dynamic>> checkDependencies() async {
    return {
      'ffmpeg': false,
      'tesseract': false,
      'python': false,
      'embedding': false,
      'ollamaInstalled': false,
      'ollamaModels': <String>[],
    };
  }
}

void main() {
  group('CuratedModel.matchesSystemSpecs Tests', () {
    test('Low ram model matches low specs', () {
      const model = CuratedModel(
        id: 'low-ram-model',
        name: 'Low RAM Model',
        category: 'Test',
        capability: 'Test',
        size: '1.0 GB',
        sizeGb: 1.0,
        ram: '4 GB+',
        ramGb: 4,
        compatibility: 'All devices',
        description: 'Test model description',
      );

      expect(model.matchesSystemSpecs(systemRamGb: 8, hasHardwareAcceleration: true), isTrue);
      expect(model.matchesSystemSpecs(systemRamGb: 2, hasHardwareAcceleration: true), isFalse);
    });

    test('High-end model requires hardware acceleration', () {
      const model = CuratedModel(
        id: 'high-end-model',
        name: 'High End Model',
        category: 'Test',
        capability: 'Test',
        size: '8.0 GB',
        sizeGb: 8.0,
        ram: '16 GB+',
        ramGb: 16,
        compatibility: 'High-end GPUs',
        description: 'Test model description',
      );

      expect(model.matchesSystemSpecs(systemRamGb: 16, hasHardwareAcceleration: true), isTrue);
      expect(model.matchesSystemSpecs(systemRamGb: 16, hasHardwareAcceleration: false), isFalse);
    });
  });

  group('OnboardingProgress Model Tests', () {
    test('copyWith works correctly', () {
      final progress = OnboardingProgress();
      expect(progress.activeStage, OnboardingStage.welcome);
      expect(progress.selectedModelIds, contains('qwen2.5:1.5b'));

      final updated = progress.copyWith(
        activeStage: OnboardingStage.modelSelection,
        selectedModelIds: ['deepseek-r1:1.5b'],
      );

      expect(updated.activeStage, OnboardingStage.modelSelection);
      expect(updated.selectedModelIds, contains('deepseek-r1:1.5b'));
    });
  });

  group('OnboardingNotifier Logic Tests', () {
    late OnboardingNotifier notifier;
    late MockOnboardingService service;

    setUp(() {
      service = MockOnboardingService();
      notifier = OnboardingNotifier(service);
    });

    test('Initial stage is welcome', () {
      expect(notifier.state.activeStage, OnboardingStage.welcome);
    });

    test('Stage navigation works', () {
      notifier.nextStage();
      expect(notifier.state.activeStage, OnboardingStage.modelSelection);
      notifier.nextStage();
      expect(notifier.state.activeStage, OnboardingStage.summary);
      notifier.prevStage();
      expect(notifier.state.activeStage, OnboardingStage.modelSelection);
    });

    test('Toggle model selection works', () {
      // Toggle should add it
      notifier.toggleModelSelection('deepseek-r1:1.5b');
      expect(notifier.state.selectedModelIds, contains('deepseek-r1:1.5b'));

      // Toggle again should remove it
      notifier.toggleModelSelection('deepseek-r1:1.5b');
      expect(notifier.state.selectedModelIds, isNot(contains('deepseek-r1:1.5b')));
    });

    test('Size calculation adds model size correctly', () {
      notifier.toggleModelSelection('deepseek-r1:1.5b');
      final totalGb = notifier.getCalculatedDownloadSize();
      // default: 'qwen2.5:1.5b' (0.98 GB) + 'deepseek-r1:1.5b' (1.1 GB) + core requirement (1.41 GB) = 3.49 GB
      expect(totalGb, closeTo(3.49, 0.05));
    });
  });
}
