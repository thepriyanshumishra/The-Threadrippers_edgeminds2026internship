// features/tutorial/providers/tutorial_provider.dart
// Purpose: Riverpod state notifier to manage the active tutorial step.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../onboarding/services/onboarding_prefs.dart';

enum TutorialStep {
  welcome,          // Intro dialog
  createWorkspace,  // Highlight "+" button
  addSources,       // Highlight "Sources" sidebar item
  chat,             // Highlight chat input
  settings,         // Highlight "Settings" sidebar item
  done,             // Final congratulations dialog
  none,             // Disabled/Completed
}

class TutorialState {
  final bool isActive;
  final TutorialStep currentStep;

  TutorialState({
    this.isActive = false,
    this.currentStep = TutorialStep.none,
  });

  TutorialState copyWith({
    bool? isActive,
    TutorialStep? currentStep,
  }) {
    return TutorialState(
      isActive: isActive ?? this.isActive,
      currentStep: currentStep ?? this.currentStep,
    );
  }
}

final tutorialProvider = StateNotifierProvider<TutorialNotifier, TutorialState>((ref) {
  return TutorialNotifier();
});

class TutorialNotifier extends StateNotifier<TutorialState> {
  TutorialNotifier() : super(TutorialState()) {
    _checkInit();
  }

  Future<void> _checkInit() async {
    final onboardingDone = await OnboardingPrefs.isOnboardingComplete();
    final tutorialDone = await OnboardingPrefs.isTutorialComplete();
    if (onboardingDone && !tutorialDone) {
      state = TutorialState(isActive: true, currentStep: TutorialStep.welcome);
    }
  }

  void startTutorial() {
    state = TutorialState(isActive: true, currentStep: TutorialStep.welcome);
  }

  void nextStep() {
    if (!state.isActive) return;
    
    final nextIdx = state.currentStep.index + 1;
    if (nextIdx < TutorialStep.values.length - 1) {
      state = state.copyWith(currentStep: TutorialStep.values[nextIdx]);
    } else {
      finishTutorial();
    }
  }

  Future<void> skipTutorial() async {
    state = TutorialState(isActive: false, currentStep: TutorialStep.none);
    await OnboardingPrefs.write({'tutorialCompleted': true});
  }

  Future<void> finishTutorial() async {
    state = TutorialState(isActive: false, currentStep: TutorialStep.none);
    await OnboardingPrefs.write({'tutorialCompleted': true});
  }

  void setStep(TutorialStep step) {
    if (state.isActive) {
      state = state.copyWith(currentStep: step);
    }
  }
}

class TutorialKeys {
  TutorialKeys._();
  static final logo = GlobalKey(debugLabel: 'logoKey');
  static final createWorkspace = GlobalKey(debugLabel: 'createWorkspaceKey');
  static final addSources = GlobalKey(debugLabel: 'addSourcesKey');
  static final pdfSourceCard = GlobalKey(debugLabel: 'pdfSourceCardKey');
  static final chatInput = GlobalKey(debugLabel: 'chatInputKey');
  static final settingsBtn = GlobalKey(debugLabel: 'settingsBtnKey');
}

