import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_workspace/features/tutorial/providers/tutorial_provider.dart';

void main() {
  group('Tutorial State and Notifier Tests', () {
    test('Initial state is inactive and none', () {
      final notifier = TutorialNotifier();
      expect(notifier.state.isActive, isFalse);
      expect(notifier.state.currentStep, TutorialStep.none);
    });

    test('startTutorial starts at welcome', () {
      final notifier = TutorialNotifier();
      notifier.startTutorial();
      expect(notifier.state.isActive, isTrue);
      expect(notifier.state.currentStep, TutorialStep.welcome);
    });

    test('nextStep transitions sequentially', () {
      final notifier = TutorialNotifier();
      notifier.startTutorial(); // welcome

      notifier.nextStep(); // createWorkspace
      expect(notifier.state.currentStep, TutorialStep.createWorkspace);

      notifier.nextStep(); // addSources
      expect(notifier.state.currentStep, TutorialStep.addSources);

      notifier.nextStep(); // chat
      expect(notifier.state.currentStep, TutorialStep.chat);

      notifier.nextStep(); // settings
      expect(notifier.state.currentStep, TutorialStep.settings);

      notifier.nextStep(); // done
      expect(notifier.state.currentStep, TutorialStep.done);

      notifier.nextStep(); // should finish and become inactive/none
      expect(notifier.state.isActive, isFalse);
      expect(notifier.state.currentStep, TutorialStep.none);
    });

    test('skipTutorial deactivates immediately', () async {
      final notifier = TutorialNotifier();
      notifier.startTutorial();
      expect(notifier.state.isActive, isTrue);

      await notifier.skipTutorial();
      expect(notifier.state.isActive, isFalse);
      expect(notifier.state.currentStep, TutorialStep.none);
    });

    test('setStep updates step directly if active', () {
      final notifier = TutorialNotifier();
      notifier.startTutorial();

      notifier.setStep(TutorialStep.chat);
      expect(notifier.state.currentStep, TutorialStep.chat);
    });
  });
}
