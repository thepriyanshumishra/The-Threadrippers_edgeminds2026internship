// features/onboarding/screens/onboarding_screen.dart
// Purpose: 6-stage onboarding UI — Welcome → Model Selection → Summary → Downloading → Customization → Done

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/font_provider.dart';
import '../../../core/theme/theme_provider.dart';
import '../models/onboarding_state.dart';
import '../providers/onboarding_provider.dart';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/utils/eyedropper_helper.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  // Appearance local selection state
  ThemeMode _selectedTheme = ThemeMode.dark;
  AppFontFamily _selectedFont = AppFontFamily.sans;
  Color _selectedAccent = const Color(0xFF0075DE);

  // Model Selection sidebar state
  String _selectedCategory = 'Recommended';
  bool _isCheckingSpecs = false;

  // Custom model state
  final TextEditingController _customModelController = TextEditingController();
  bool _isValidatingCustomModel = false;
  String? _customModelError;
  CuratedModel? _verifiedCustomModel;

  final List<Color> _accentColors = [
    const Color(0xFF0075DE), // Blue
    const Color(0xFF0F7B44), // Green
    const Color(0xFF6366F1), // Indigo
    const Color(0xFFE11D48), // Crimson
  ];

  @override
  void initState() {
    super.initState();
    _selectedTheme = ref.read(themeModeProvider);
    _selectedFont = ref.read(fontProvider);
    _selectedAccent = ref.read(accentColorProvider);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(onboardingProvider.notifier).refreshOllamaStatus();
    });
  }

  @override
  void dispose() {
    _customModelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final progress = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);

    debugPrint('DEBUG: installedOllamaModels = ${progress.installedOllamaModels}');
    debugPrint('DEBUG: selectedModelIds = ${progress.selectedModelIds}');


    // Live-preview theme changes on customization and done screens
    if (progress.activeStage == OnboardingStage.customization ||
        progress.activeStage == OnboardingStage.done) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ref.read(themeModeProvider) != _selectedTheme) {
          ref.read(themeModeProvider.notifier).state = _selectedTheme;
        }
        if (ref.read(fontProvider) != _selectedFont) {
          ref.read(fontProvider.notifier).state = _selectedFont;
        }
        if (ref.read(accentColorProvider) != _selectedAccent) {
          ref.read(accentColorProvider.notifier).state = _selectedAccent;
        }
      });
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            // --- TOP STAGES TIMELINE ---
            _buildTimeline(progress.activeStage, colors),
            const Divider(height: 1),

            // --- STAGE SCREEN ---
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: _buildStageContent(progress, notifier, colors),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TIMELINE HEADER
  // ─────────────────────────────────────────────────────────────
  Widget _buildTimeline(OnboardingStage currentStage, AppColors colors) {
    final stages = ['Welcome', 'Models', 'Summary', 'Download', 'Customize', 'Done'];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(color: colors.sidebarBackground),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(stages.length, (index) {
          final isCompleted = index < currentStage.index;
          final isActive = index == currentStage.index;

          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? colors.primary
                        : isActive
                            ? colors.primary
                            : colors.border,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: isCompleted
                      ? const Icon(Icons.check, size: 12, color: Colors.white)
                      : Text(
                          (index + 1).toString(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isActive ? Colors.white : colors.textSecondary,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    stages[index],
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      color: isActive ? colors.textPrimary : colors.textMuted,
                    ),
                  ),
                ),
                if (index < stages.length - 1)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Container(
                        height: 2,
                        color: isCompleted ? colors.primary : colors.border,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STAGE ROUTER
  // ─────────────────────────────────────────────────────────────
  Widget _buildStageContent(OnboardingProgress progress, OnboardingNotifier notifier, AppColors colors) {
    switch (progress.activeStage) {
      case OnboardingStage.welcome:
        return _buildWelcome(notifier, colors);
      case OnboardingStage.modelSelection:
        return _buildModelSelection(progress, notifier, colors);
      case OnboardingStage.summary:
        return _buildSummary(progress, notifier, colors);
      case OnboardingStage.downloading:
        return _buildDownloading(progress, notifier, colors);
      case OnboardingStage.customization:
        return _buildCustomization(progress, notifier, colors);
      case OnboardingStage.done:
        return _buildDone(colors);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // STAGE 1: WELCOME
  // ─────────────────────────────────────────────────────────────
  Widget _buildWelcome(OnboardingNotifier notifier, AppColors colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 32),

        // Logo
        Image.asset(
          'assets/images/app_logo.png',
          width: 80,
          height: 80,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 28),

        const Text(
          'Welcome to Kivo Workspace',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        const SizedBox(height: 16),
        Text(
          'Your edge-first AI knowledge workspace.\nAll models run entirely on your device — private, fast, and offline-ready.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: colors.textSecondary, height: 1.55),
        ),
        const SizedBox(height: 40),

        // Feature highlights
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _featureChip(Icons.lock_outline_rounded, 'Fully Private', colors),
            const SizedBox(width: 12),
            _featureChip(Icons.bolt_rounded, 'Edge-Optimized', colors),
            const SizedBox(width: 12),
            _featureChip(Icons.wifi_off_rounded, 'Works Offline', colors),
          ],
        ),
        const SizedBox(height: 52),

        SizedBox(
          width: 240,
          height: 52,
          child: ElevatedButton(
            onPressed: _isCheckingSpecs ? null : () async {
              setState(() => _isCheckingSpecs = true);
              await notifier.refreshOllamaStatus();
              if (mounted) {
                setState(() => _isCheckingSpecs = false);
                notifier.nextStage();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: _isCheckingSpecs 
                ? const SizedBox(
                    width: 20, 
                    height: 20, 
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Get Started', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _featureChip(IconData icon, String label, AppColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colors.sidebarBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.primary),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textPrimary)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STAGE 2: MODEL SELECTION
  // ─────────────────────────────────────────────────────────────
  Widget _buildModelSelection(OnboardingProgress progress, OnboardingNotifier notifier, AppColors colors) {
    // RAM-based recommendation helpers (kept for smart defaults)
    int getRamBucket(int ramGb) {
      if (ramGb <= 4) return 4;
      if (ramGb <= 8) return 8;
      if (ramGb <= 16) return 16;
      if (ramGb <= 24) return 24;
      if (ramGb <= 48) return 48;
      return 96;
    }

    List<int> getRecommendedRamBuckets(double systemRamGb) {
      final ramLevels = [4, 8, 16, 24, 48, 96];
      final lowerLevels = ramLevels.where((l) => l < systemRamGb).toList();
      if (lowerLevels.isEmpty) return [4];
      if (lowerLevels.length == 1) return [lowerLevels.first];
      return [lowerLevels[lowerLevels.length - 2], lowerLevels[lowerLevels.length - 1]];
    }

    // Default to 8GB if system specs not fetched
    const systemRamGb = 8.0;
    final allowedBuckets = getRecommendedRamBuckets(systemRamGb);

    // Build recommended: 2 models from each of 3 key categories
    final targetCategories = ['General Chat & Assistant', 'Reasoning & Logic', 'Coding & Technical'];
    final List<CuratedModel> recommendedModels = [];
    final Set<String> recIds = {};
    for (final cat in targetCategories) {
      final catModels = curatedModelRegistry.where((m) => m.category == cat).toList();
      final matching = catModels.where((m) {
        final bucket = getRamBucket(m.ramGb);
        return allowedBuckets.contains(bucket);
      }).toList();
      int count = 0;
      for (final m in matching) {
        if (count >= 2) break;
        if (!recIds.contains(m.id)) { recommendedModels.add(m); recIds.add(m.id); count++; }
      }
      if (count < 2) {
        for (final m in catModels) {
          if (count >= 2) break;
          if (!recIds.contains(m.id)) { recommendedModels.add(m); recIds.add(m.id); count++; }
        }
      }
    }

    // Build installed models list dynamically from local Ollama tags
    final List<CuratedModel> installedModels = [];
    for (final tag in progress.installedOllamaModels) {
      final match = curatedModelRegistry.firstWhere(
        (m) => m.id == tag,
        orElse: () => curatedModelRegistry.firstWhere(
          (m) => m.id.split(':').first == tag.split(':').first,
          orElse: () {
            String cleanName = tag;
            if (cleanName.endsWith(':latest')) {
              cleanName = cleanName.replaceAll(':latest', '');
            }
            return CuratedModel(
              id: tag,
              name: cleanName,
              category: 'Installed',
              capability: 'Local Model',
              size: 'Installed',
              sizeGb: 0.0,
              ram: 'Unknown',
              ramGb: 0,
              compatibility: 'All devices',
              description: 'Installed local model detected from Ollama.',
            );
          },
        ),
      );
      if (!installedModels.any((m) => m.id == match.id)) {
        installedModels.add(match);
      }
    }

    // Reset tab if installed tab is empty (due to deletion)
    if (_selectedCategory == 'Installed' && installedModels.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _selectedCategory = 'Recommended';
        });
      });
    }

    // Build ordered category list
    final allCatSet = curatedModelRegistry.map((m) => m.category).toSet();
    final categoryOrder = [
      'Installed', 'Recommended', 'General Chat & Assistant', 'Reasoning & Logic', 'Coding & Technical',
      'Creative & Narrative', 'Educational & Information', 'Summarization', 'High-Capacity Reasoners',
      'Agentic & Tool-Use', 'Roleplay & Storytelling', 'Speed & Low-Resource',
      'Medical & Science', 'Multilingual & Translation', 'Uncensored', 'Custom',
    ];
    final categories = [
      if (progress.installedOllamaModels.isNotEmpty) 'Installed',
      'Recommended',
      ...allCatSet
    ];
    debugPrint('DEBUG: categories constructed = $categories');
    categories.sort((a, b) {
      final ia = categoryOrder.indexOf(a); final ib = categoryOrder.indexOf(b);
      return (ia == -1 ? 99 : ia).compareTo(ib == -1 ? 99 : ib);
    });
    debugPrint('DEBUG: categories sorted = $categories');


    final List<CuratedModel> currentModels;
    if (_selectedCategory == 'Installed') {
      currentModels = installedModels;
    } else if (_selectedCategory == 'Recommended') {
      currentModels = recommendedModels;
    } else {
      currentModels = curatedModelRegistry.where((m) => m.category == _selectedCategory).toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Local Models',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose one or more local LLMs to download. Switch between them seamlessly inside your chats.',
          style: TextStyle(fontSize: 14, color: colors.textSecondary),
        ),
        const SizedBox(height: 24),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Category Sidebar
            SizedBox(
              width: 210,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: categories.map((cat) {
                  final isSel = _selectedCategory == cat;
                  final selCount = cat == 'Recommended'
                      ? progress.selectedModelIds.where((id) => recIds.contains(id)).length
                      : progress.selectedModelIds.where((id) {
                          final m = curatedModelRegistry.firstWhere((m) => m.id == id, orElse: () => curatedModelRegistry[0]);
                          return m.category == cat;
                        }).length;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: InkWell(
                      onTap: () => setState(() => _selectedCategory = cat),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        decoration: BoxDecoration(
                          color: isSel ? colors.primary.withValues(alpha: 0.1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 3, height: 14,
                              decoration: BoxDecoration(
                                color: isSel ? colors.primary : Colors.transparent,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                cat,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                  color: isSel ? colors.primary : colors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (selCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(10)),
                                child: Text('$selCount', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // Vertical divider
            Container(width: 1, height: 520, color: colors.border, margin: const EdgeInsets.symmetric(horizontal: 16)),

            // Right content area
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedCategory == 'Recommended' ? '⭐ Recommended' : _selectedCategory,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  if (_selectedCategory == 'Custom') ..._buildCustomModelPanel(notifier, progress, colors)
                  else if (currentModels.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('No models in this category.', style: TextStyle(color: colors.textMuted))),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: currentModels.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 2.1,
                      ),
                      itemBuilder: (context, idx) {
                        if (_selectedCategory == 'Installed') {
                          return _buildInstalledModelCard(currentModels[idx], progress, notifier, colors);
                        }
                        return _buildCompactModelCard(currentModels[idx], progress, notifier, colors);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 40),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(
              onPressed: () => notifier.prevStage(),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: progress.selectedModelIds.isEmpty ? null : () => notifier.nextStage(),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: const Text('Next: Review Summary'),
            ),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STAGE 3: SUMMARY (models only)
  // ─────────────────────────────────────────────────────────────
  Widget _buildSummary(OnboardingProgress progress, OnboardingNotifier notifier, AppColors colors) {
    final downloadSize = notifier.getCalculatedDownloadSize();
    final diskFootprint = downloadSize * 1.05; // ~5% overhead for Ollama blobs

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Download Summary',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        const SizedBox(height: 8),
        Text(
          'Review the models selected for download. Everything runs locally on your device.',
          style: TextStyle(fontSize: 14, color: colors.textSecondary),
        ),
        const SizedBox(height: 24),

        // Models list
        Container(
          decoration: BoxDecoration(
            color: colors.sidebarBackground,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              // Section header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.psychology_rounded, size: 16, color: colors.primary),
                    const SizedBox(width: 8),
                    Text('AI Models to Download', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colors.textPrimary)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: colors.primarySubtle, borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        '${progress.selectedModelIds.length} selected',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colors.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ...progress.selectedModelIds.map((id) {
                final match = curatedModelRegistry.firstWhere(
                  (m) => m.id == id,
                  orElse: () => curatedModelRegistry[0],
                );
                final isAlreadyInstalled = progress.installedOllamaModels.any(
                  (m) => m == id || m.startsWith('$id:') || id.startsWith('$m:'),
                );
                return _summaryModelTile(match, isAlreadyInstalled, colors);
              }),

              // Ollama row
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  progress.isOllamaInstalled ? Icons.check_circle : Icons.terminal_rounded, 
                  size: 16, 
                  color: progress.isOllamaInstalled ? colors.statusReady : colors.primary,
                ),
                title: const Text('Ollama Engine', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                subtitle: Text(
                  progress.isOllamaInstalled ? 'Already installed on your device' : 'Required to run local LLMs', 
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
                trailing: Text(
                  progress.isOllamaInstalled ? 'Installed' : '~300 MB', 
                  style: TextStyle(
                    fontWeight: FontWeight.w600, 
                    fontSize: 12.5, 
                    color: progress.isOllamaInstalled ? colors.statusReady : colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Disk info banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colors.primarySubtle,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.storage_rounded, size: 18, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Total download: ${_formatDownloadSize(downloadSize)}  ·  Disk footprint: ~${_formatDownloadSize(diskFootprint)}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.primary),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 40),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(
              onPressed: () => notifier.prevStage(),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: () => notifier.nextStage(),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: const Text('Start Downloading'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryModelTile(CuratedModel model, bool isInstalled, AppColors colors) {
    return ListTile(
      leading: Icon(
        isInstalled ? Icons.check_circle : Icons.download_rounded,
        size: 16,
        color: isInstalled ? colors.statusReady : colors.primary,
      ),
      title: Text(model.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
      subtitle: Text(
        isInstalled ? 'Already installed — will be skipped' : model.description,
        style: TextStyle(fontSize: 11, color: colors.textSecondary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        isInstalled ? 'Installed' : model.size,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: isInstalled ? colors.statusReady : colors.textPrimary),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STAGE 4: DOWNLOADING
  // ─────────────────────────────────────────────────────────────
  Widget _buildDownloading(OnboardingProgress progress, OnboardingNotifier notifier, AppColors colors) {
    final isDone = progress.downloadProgress >= 1.0;
    final isDownloading = progress.isDownloading && !progress.downloadCancelled;
    
    final currentModelEntry = progress.installStatus.entries
        .where((e) => e.value.contains('Downloading'))
        .firstOrNull;
    final currentModelId = currentModelEntry?.key;
    final currentModel = currentModelId != null
        ? curatedModelRegistry.firstWhere((m) => m.id == currentModelId, orElse: () => curatedModelRegistry[0])
        : null;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),

        Text(
          isDone ? 'Download Complete!' : (progress.downloadCancelled ? 'Download Paused' : 'Downloading Models'),
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        const SizedBox(height: 8),
        Text(
          isDone
              ? 'All selected models are ready. Let\'s personalize your workspace.'
              : (progress.downloadCancelled 
                  ? 'The download has been paused/cancelled. You can resume or proceed.'
                  : 'Please keep the app open. Models are being pulled from Ollama.'),
          style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
        ),
        const SizedBox(height: 36),

        // Currently downloading model indicator
        if (!isDone && currentModel != null && isDownloading) ...[
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                'Pulling: ${currentModel.name}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.primary),
              ),
              const SizedBox(width: 8),
              Text(currentModel.size, style: TextStyle(fontSize: 12, color: colors.textSecondary)),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // Speed & ETA row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.speed_rounded, size: 14, color: colors.textSecondary),
                const SizedBox(width: 5),
                Text(
                  isDone 
                      ? 'Done' 
                      : (isDownloading ? '${progress.downloadSpeed.toStringAsFixed(1)} MB/s' : '0.0 MB/s'),
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
              ],
            ),
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 14, color: colors.textSecondary),
                const SizedBox(width: 5),
                Text(
                  isDone 
                      ? '0s remaining' 
                      : (isDownloading ? '${progress.downloadEta} remaining' : 'Paused'),
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: isDone ? 1.0 : progress.downloadProgress,
            minHeight: 14,
            backgroundColor: colors.border,
            valueColor: AlwaysStoppedAnimation<Color>(
              isDone 
                ? colors.statusReady 
                : (isDownloading ? colors.primary : colors.textMuted)
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '${progress.downloadedMb.toStringAsFixed(0)} MB / ${progress.totalMb.toStringAsFixed(0)} MB',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: colors.textPrimary),
            ),
          ],
        ),

        // Per-model status list
        if (progress.installStatus.isNotEmpty) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.sidebarBackground,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: progress.installStatus.entries.map((entry) {
                final isModelDone = entry.value.contains('Ready') || entry.value.contains('✅') || entry.value.contains('Installed');
                final isInProgress = entry.value.contains('Downloading') && isDownloading;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      if (isInProgress)
                        SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
                        )
                      else
                        Icon(
                          isModelDone ? Icons.check_circle : Icons.radio_button_unchecked,
                          size: 14,
                          color: isModelDone ? colors.statusReady : colors.textMuted,
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entry.key,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        isInProgress ? entry.value : (isModelDone ? 'Installed ✅' : 'Paused'),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isInProgress ? colors.primary : isModelDone ? colors.statusReady : colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],

        // Cancel / Retry Circular Button block
        if (!isDone) ...[
          const SizedBox(height: 28),
          if (isDownloading)
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        backgroundColor: colors.sidebarBackground,
                        title: Text(
                          'Cancel Download?',
                          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold),
                        ),
                        content: Text(
                          'Are you sure you want to stop downloading? You can resume later, go back to change models, or skip to the next step.',
                          style: TextStyle(color: colors.textSecondary),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text('Keep Downloading', style: TextStyle(color: colors.primary)),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              notifier.cancelDownload();
                            },
                            child: const Text('Cancel Download', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      );
                    },
                  );
                },
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('Cancel Download', style: TextStyle(fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            )
          else
            Center(
              child: Column(
                children: [
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, size: 48, color: colors.primary),
                    onPressed: () => notifier.startDownloading(),
                    tooltip: 'Resume/Retry Download',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    progress.downloadCancelled 
                      ? 'Download paused. Click to resume.' 
                      : 'Download failed/paused. Click to retry.',
                    style: TextStyle(fontSize: 12.5, color: colors.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],

        // No internet banner
        if (!progress.isInternetConnected)
          Container(
            margin: const EdgeInsets.only(top: 24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.statusFailedBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.statusFailed),
            ),
            child: Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: colors.statusFailed),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No Internet Connection', style: TextStyle(fontWeight: FontWeight.bold, color: colors.statusFailed, fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text('Please check your network and retry.', style: TextStyle(color: colors.statusFailed, fontSize: 12)),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => notifier.retryDownload(),
                  style: ElevatedButton.styleFrom(backgroundColor: colors.statusFailed, foregroundColor: Colors.white),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),

        // General error banner
        if (progress.errorMessage != null && !progress.downloadCancelled)
          Container(
            margin: const EdgeInsets.only(top: 24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.statusFailedBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.statusFailed),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: colors.statusFailed),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Download Failed', style: TextStyle(fontWeight: FontWeight.bold, color: colors.statusFailed, fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text(progress.errorMessage!, style: TextStyle(color: colors.statusFailed, fontSize: 12)),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => notifier.startDownloading(),
                  style: ElevatedButton.styleFrom(backgroundColor: colors.statusFailed, foregroundColor: Colors.white),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),

        // Bottom Back/Next navigation buttons (only show when not actively downloading)
        if (!isDownloading) ...[
          const SizedBox(height: 36),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton(
                onPressed: () => notifier.prevStage(),
                child: const Text('Back'),
              ),
              ElevatedButton(
                onPressed: () => notifier.nextStage(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                child: const Text('Next: Customize'),
              ),
            ],
          ),
        ],

        const SizedBox(height: 60),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STAGE 5: CUSTOMIZATION (merged Config + Appearance)
  // ─────────────────────────────────────────────────────────────
  Widget _buildCustomization(OnboardingProgress progress, OnboardingNotifier notifier, AppColors colors) {
    final isDark = _selectedTheme == ThemeMode.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Personalize Your Workspace',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Configure your theme, typography, and accent color. You can change these anytime in Settings.',
          style: TextStyle(fontSize: 14, color: colors.textSecondary),
        ),
        const SizedBox(height: 32),

        // 1. Theme selection
        const Text('Theme Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),
        Row(
          children: [
            _outlinedButtonIcon(
              onPressed: () {
                setState(() => _selectedTheme = ThemeMode.light);
                ref.read(themeModeProvider.notifier).state = ThemeMode.light;
              },
              icon: Icons.light_mode_outlined,
              label: 'Light Mode',
              isSelected: _selectedTheme == ThemeMode.light,
              colors: colors,
            ),
            const SizedBox(width: 16),
            _outlinedButtonIcon(
              onPressed: () {
                setState(() => _selectedTheme = ThemeMode.dark);
                ref.read(themeModeProvider.notifier).state = ThemeMode.dark;
              },
              icon: Icons.dark_mode_outlined,
              label: 'Dark Mode',
              isSelected: _selectedTheme == ThemeMode.dark,
              colors: colors,
            ),
          ],
        ),
        const SizedBox(height: 28),

        // 2. Typography
        const Text('Active Typography', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),
        SegmentedButton<AppFontFamily>(
          segments: const [
            ButtonSegment(value: AppFontFamily.sans, label: Text('Sans Serif')),
            ButtonSegment(value: AppFontFamily.serif, label: Text('Serif')),
            ButtonSegment(value: AppFontFamily.mono, label: Text('Mono (Stealth)')),
          ],
          selected: {_selectedFont},
          onSelectionChanged: (val) {
            setState(() => _selectedFont = val.first);
            ref.read(fontProvider.notifier).state = val.first;
          },
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
          ),
        ),
        const SizedBox(height: 28),

        // 3. Accent highlight
        const Text('Accent Highlight Color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),
        Row(
          children: [
            ..._accentColors.map((color) {
              final isSelected = _selectedAccent == color;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedAccent = color);
                  ref.read(accentColorProvider.notifier).state = color;
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 16),
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: isDark ? Colors.white : Colors.black, width: 2.5)
                        : Border.all(color: Colors.transparent),
                  ),
                ),
              );
            }),
            // Custom palette picker
            GestureDetector(
              onTap: () => _showCustomColorPickerDialog(context, colors),
              child: Tooltip(
                message: 'Custom Color Palette',
                child: Container(
                  margin: const EdgeInsets.only(right: 16),
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: !_accentColors.contains(_selectedAccent)
                          ? (isDark ? Colors.white : Colors.black)
                          : colors.border,
                      width: !_accentColors.contains(_selectedAccent) ? 2.5 : 1,
                    ),
                    gradient: const SweepGradient(
                      colors: [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Color(0xFFFF00FF), Colors.red],
                    ),
                  ),
                  child: Icon(
                    Icons.palette_rounded,
                    size: 16,
                    color: !_accentColors.contains(_selectedAccent)
                        ? (isDark ? Colors.white : Colors.black)
                        : Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
            // Eyedropper
            GestureDetector(
              onTap: () async {
                final Color? picked = await EyedropperHelper.pickColor(context);
                if (picked != null) {
                  setState(() => _selectedAccent = picked);
                  ref.read(accentColorProvider.notifier).state = picked;
                }
              },
              child: Tooltip(
                message: 'Pick Color from Screen',
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.border),
                    color: colors.sidebarBackground,
                  ),
                  child: Icon(Icons.colorize_rounded, size: 16, color: colors.textPrimary),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 48),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _selectedTheme = ThemeMode.dark;
                  _selectedFont = AppFontFamily.sans;
                  _selectedAccent = const Color(0xFF0075DE);
                });
                ref.read(themeModeProvider.notifier).state = ThemeMode.dark;
                ref.read(fontProvider.notifier).state = AppFontFamily.sans;
                ref.read(accentColorProvider.notifier).state = const Color(0xFF0075DE);
              },
              child: const Text('Restore Defaults'),
            ),
            ElevatedButton(
              onPressed: () {
                notifier.completeOnboarding(
                  theme: _selectedTheme,
                  font: _selectedFont.name,
                  accentHex: '#${_selectedAccent.toARGB32().toRadixString(16).substring(2)}',
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              ),
              child: const Text('Finish Setup'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _outlinedButtonIcon({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required bool isSelected,
    required AppColors colors,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: isSelected ? colors.primary : colors.textSecondary),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: isSelected ? colors.primary : colors.textSecondary,
        side: BorderSide(color: isSelected ? colors.primary : colors.border, width: isSelected ? 2 : 1),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STAGE 6: DONE
  // ─────────────────────────────────────────────────────────────
  Widget _buildDone(AppColors colors) {
    final progress = ref.watch(onboardingProvider);
    final themeLabel = _selectedTheme == ThemeMode.dark ? 'Dark Mode' : 'Light Mode';
    final fontLabel = _selectedFont == AppFontFamily.sans 
        ? 'Sans Serif' 
        : _selectedFont == AppFontFamily.serif 
            ? 'Serif' 
            : 'Mono (Stealth)';
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        
        // App Logo with a glowing subtle background
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colors.primary.withValues(alpha: 0.15),
                    colors.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            Image.asset(
              'assets/images/app_logo.png',
              width: 90,
              height: 90,
              fit: BoxFit.contain,
            ),
          ],
        ),
        const SizedBox(height: 32),

        const Text(
          'You\'re All Set! 🚀',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 32, 
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Kivo Workspace is ready. Your custom environment is configured\nand all AI models will run privately on your device.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15, 
            color: colors.textSecondary, 
            height: 1.5,
          ),
        ),
        const SizedBox(height: 36),

        // Setup Summary Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.sidebarBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CONFIGURATION SUMMARY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: colors.textMuted,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 16),
              _summaryRow(Icons.color_lens_outlined, 'Appearance Theme', themeLabel, colors),
              const SizedBox(height: 12),
              _summaryRow(Icons.font_download_outlined, 'Workspace Typography', fontLabel, colors),
              const SizedBox(height: 12),
              _summaryRow(
                Icons.memory_rounded, 
                'Local Models Installed', 
                '${progress.selectedModelIds.length} active ${progress.selectedModelIds.length == 1 ? 'model' : 'models'}', 
                colors
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),

        // Launch Action Button
        SizedBox(
          width: 240,
          height: 54,
          child: ElevatedButton(
            onPressed: () {
              ref.read(themeModeProvider.notifier).state = _selectedTheme;
              ref.read(fontProvider.notifier).state = _selectedFont;
              ref.read(accentColorProvider.notifier).state = _selectedAccent;
              context.go('/');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Open Workspace', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                SizedBox(width: 8),
                Icon(Icons.rocket_launch_rounded, size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _summaryRow(IconData icon, String title, String value, AppColors colors) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Icon(icon, size: 16, color: colors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(fontSize: 13, color: colors.textSecondary, fontWeight: FontWeight.w500),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: colors.primarySubtle,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colors.primary,
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MODEL CARDS
  // ─────────────────────────────────────────────────────────────
  List<Widget> _buildCustomModelPanel(OnboardingNotifier notifier, OnboardingProgress progress, AppColors colors) {
    return [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.sidebarBackground,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Import Custom Ollama Model', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'Enter any public Ollama model ID (e.g. llama3:8b) or paste the full pull command (e.g. ollama pull mistral). Kivo will verify compatibility before queuing for download.',
              style: TextStyle(fontSize: 12, color: colors.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _customModelController,
              decoration: InputDecoration(
                labelText: 'Model ID or Pull Command',
                hintText: 'e.g. llama3.2:3b  or  ollama pull gemma3:4b',
                labelStyle: TextStyle(color: colors.textSecondary, fontSize: 13),
                hintStyle: TextStyle(color: colors.textMuted, fontSize: 12),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.primary, width: 2)),
                errorText: _customModelError,
                errorMaxLines: 3,
              ),
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
              onSubmitted: (val) => _validateAndAddCustomModel(val, notifier),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton(
                onPressed: _isValidatingCustomModel
                    ? null
                    : () => _validateAndAddCustomModel(_customModelController.text, notifier),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isValidatingCustomModel
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                    : const Text('Get Details', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
      if (_verifiedCustomModel != null) ...[
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.check_circle, color: colors.statusReady, size: 16),
            const SizedBox(width: 6),
            Text('Verified — model selected!', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.statusReady)),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(height: 120, child: _buildCompactModelCard(_verifiedCustomModel!, progress, notifier, colors)),
      ],
    ];
  }

  Widget _buildCompactModelCard(CuratedModel model, OnboardingProgress progress, OnboardingNotifier notifier, AppColors colors) {
    final isSelected = progress.selectedModelIds.contains(model.id);
    final Color ramText;
    final Color ramBg;
    if (model.ramGb <= 4) { ramText = colors.statusReady; ramBg = colors.statusReadyBg; }
    else if (model.ramGb <= 8) { ramText = colors.primary; ramBg = colors.primarySubtle; }
    else if (model.ramGb <= 16) { ramText = colors.statusProcessing; ramBg = colors.statusProcessingBg; }
    else { ramText = colors.statusFailed; ramBg = colors.statusFailedBg; }

    return InkWell(
      onTap: () => notifier.toggleModelSelection(model.id),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? colors.primary.withValues(alpha: 0.05) : colors.background,
          border: Border.all(color: isSelected ? colors.primary : colors.border, width: isSelected ? 2 : 1),
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected ? [BoxShadow(color: colors.primary.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 4))] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(model.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5), overflow: TextOverflow.ellipsis),
                      Text(model.capability, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: colors.textMuted), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Transform.scale(
                  scale: 0.85,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => notifier.toggleModelSelection(model.id),
                    activeColor: colors.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(model.description, style: TextStyle(fontSize: 9.5, color: colors.textSecondary, height: 1.25), maxLines: 2, overflow: TextOverflow.ellipsis),
            const Spacer(),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: colors.sidebarBackground, borderRadius: BorderRadius.circular(4), border: Border.all(color: colors.border)),
                  child: Text(model.size, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: colors.textSecondary)),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: ramBg, borderRadius: BorderRadius.circular(4)),
                  child: Text('RAM: ${model.ram}', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: ramText)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDownloadSize(double sizeGb) {
    if (sizeGb < 1.0) {
      return '${(sizeGb * 1000).toStringAsFixed(0)} MB';
    } else {
      return '${sizeGb.toStringAsFixed(1)} GB';
    }
  }

  Widget _buildInstalledModelCard(
    CuratedModel model, 
    OnboardingProgress progress, 
    OnboardingNotifier notifier, 
    AppColors colors
  ) {
    final isSelected = progress.selectedModelIds.contains(model.id);
    bool isDeleting = false;

    return StatefulBuilder(
      builder: (context, setCardState) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? colors.primary.withValues(alpha: 0.05) : colors.background,
            border: Border.all(color: isSelected ? colors.primary : colors.border, width: isSelected ? 2 : 1),
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected ? [BoxShadow(color: colors.primary.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 4))] : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.name, 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5), 
                          overflow: TextOverflow.ellipsis
                        ),
                        Text(
                          model.capability, 
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: colors.textMuted), 
                          overflow: TextOverflow.ellipsis
                        ),
                      ],
                    ),
                  ),
                  Transform.scale(
                    scale: 0.85,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (_) => notifier.toggleModelSelection(model.id),
                      activeColor: colors.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                model.description, 
                style: TextStyle(fontSize: 9.5, color: colors.textSecondary, height: 1.25), 
                maxLines: 2, 
                overflow: TextOverflow.ellipsis
              ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.statusReadyBg, 
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: colors.statusReady.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'Installed', 
                      style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: colors.statusReady)
                    ),
                  ),
                  const Spacer(),
                  if (isDeleting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.red)),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      tooltip: 'Delete Model',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: colors.background,
                            title: const Text('Delete Model', style: TextStyle(fontWeight: FontWeight.bold)),
                            content: Text('Are you sure you want to delete ${model.name} from your local Ollama engine? This action cannot be undone.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          setCardState(() => isDeleting = true);
                          await notifier.deleteInstalledModel(model.id);
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
        );
      }
    );
  }

  // ─────────────────────────────────────────────────────────────
  // CUSTOM MODEL HELPERS
  // ─────────────────────────────────────────────────────────────
  String _extractModelId(String input) {
    final trimmed = input.trim();
    final pullPrefixRegex = RegExp(r'^ollama\s+pull\s+', caseSensitive: false);
    if (pullPrefixRegex.hasMatch(trimmed)) {
      return trimmed.replaceFirst(pullPrefixRegex, '').trim();
    }
    return trimmed;
  }

  Future<String> _resolveDefaultTag(String modelPath) async {
    try {
      final tagsUrl = Uri.parse('https://ollama.com/library/${modelPath.replaceFirst('library/', '')}');
      final res = await http.get(tagsUrl);
      if (res.statusCode == 200) {
        final tagsRegex = RegExp(r'data-tag="([^"]+)"');
        final tags = tagsRegex.allMatches(res.body).map((m) => m.group(1)!).toList();
        if (tags.isNotEmpty) return tags.first;
      }
    } catch (_) {}
    return 'latest';
  }

  Future<Map<String, dynamic>?> _fetchRemoteModelInfo(String id) async {
    try {
      String modelPath = id;
      String tag = 'latest';
      if (id.contains(':')) { final parts = id.split(':'); modelPath = parts[0]; tag = parts[1]; }
      if (!modelPath.contains('/')) modelPath = 'library/$modelPath';

      final manifestUrl = Uri.parse('https://registry.ollama.ai/v2/$modelPath/manifests/$tag');
      var res = await http.get(manifestUrl, headers: {'Accept': 'application/vnd.docker.distribution.manifest.v2+json'});

      if (res.statusCode == 401) {
        final tokenUrl = Uri.parse('https://registry.ollama.ai/v2/token?service=registry.ollama.ai&scope=repository:$modelPath:pull');
        final tokenRes = await http.get(tokenUrl);
        if (tokenRes.statusCode == 200) {
          final token = jsonDecode(tokenRes.body)['token'] as String?;
          if (token != null) {
            res = await http.get(manifestUrl, headers: {'Authorization': 'Bearer $token', 'Accept': 'application/vnd.docker.distribution.manifest.v2+json'});
          }
        }
      }

      if (res.statusCode != 200 && !id.contains(':')) {
        final resolvedTag = await _resolveDefaultTag(modelPath);
        if (resolvedTag != 'latest') {
          tag = resolvedTag;
          final retryUrl = Uri.parse('https://registry.ollama.ai/v2/$modelPath/manifests/$tag');
          res = await http.get(retryUrl, headers: {'Accept': 'application/vnd.docker.distribution.manifest.v2+json'});
          if (res.statusCode == 401) {
            final tokenUrl = Uri.parse('https://registry.ollama.ai/v2/token?service=registry.ollama.ai&scope=repository:$modelPath:pull');
            final tokenRes = await http.get(tokenUrl);
            if (tokenRes.statusCode == 200) {
              final token = jsonDecode(tokenRes.body)['token'] as String?;
              if (token != null) res = await http.get(retryUrl, headers: {'Authorization': 'Bearer $token', 'Accept': 'application/vnd.docker.distribution.manifest.v2+json'});
            }
          }
        }
      }

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        double totalBytes = 0;
        for (final layer in (data['layers'] as List? ?? [])) { totalBytes += (layer['size'] as num? ?? 0); }
        if (totalBytes == 0) totalBytes = (data['config']?['size'] as num? ?? 0).toDouble();
        final sizeGb = totalBytes / (1024 * 1024 * 1024);
        final sizeString = sizeGb > 0 ? '${sizeGb.toStringAsFixed(1)} GB' : 'Unknown';
        final int ramGb = sizeGb < 2.0 ? 4 : sizeGb < 3.5 ? 8 : sizeGb < 6.0 ? 16 : sizeGb < 12.0 ? 24 : 48;
        final finalId = tag == 'latest' ? id : (id.contains(':') ? id : '$id:$tag');
        return {
          'id': finalId, 'name': finalId, 'capability': 'Custom Model',
          'size': sizeString, 'sizeGb': double.parse(sizeGb.toStringAsFixed(2)),
          'ram': '$ramGb GB+', 'ramGb': ramGb,
          'compatibility': sizeGb < 6.0 ? 'All devices' : 'High-spec devices',
          'description': 'Custom model from Ollama library — dynamically fetched.',
        };
      }
    } catch (_) {}
    return null;
  }

  Future<void> _validateAndAddCustomModel(String modelId, OnboardingNotifier notifier) async {
    final cleanId = _extractModelId(modelId);
    if (cleanId.isEmpty) return;
    setState(() { _isValidatingCustomModel = true; _customModelError = null; _verifiedCustomModel = null; });

    final isMultimodal = cleanId.toLowerCase().contains(
      RegExp(r'(vision|vl|llava|bakllava|moondream|paligemma|whisper|audio|tts|bark|speech|minicpm-v|vlm|cogvlm|mplug-owl|clip)'));
    if (isMultimodal) {
      setState(() { _isValidatingCustomModel = false; _customModelError = 'Vision and audio models are not supported in Kivo Workspace.'; });
      return;
    }

    final modelInfo = await _fetchRemoteModelInfo(cleanId);
    if (modelInfo == null) {
      setState(() { _isValidatingCustomModel = false; _customModelError = 'Model ID not found. Check the ID at ollama.com/library and try again.'; });
      return;
    }

    final customModel = CuratedModel(
      id: modelInfo['id'] as String, name: modelInfo['name'] as String,
      category: 'Custom', capability: modelInfo['capability'] as String,
      size: modelInfo['size'] as String, sizeGb: modelInfo['sizeGb'] as double,
      ram: modelInfo['ram'] as String, ramGb: modelInfo['ramGb'] as int,
      compatibility: modelInfo['compatibility'] as String, description: modelInfo['description'] as String,
    );

    if (!curatedModelRegistry.any((m) => m.id == customModel.id)) curatedModelRegistry.add(customModel);
    if (!ref.read(onboardingProvider).selectedModelIds.contains(customModel.id)) notifier.toggleModelSelection(customModel.id);
    setState(() { _isValidatingCustomModel = false; _verifiedCustomModel = customModel; });
  }

  // ─────────────────────────────────────────────────────────────
  // CUSTOM COLOR PICKER DIALOG
  // ─────────────────────────────────────────────────────────────
  Future<void> _showCustomColorPickerDialog(BuildContext context, AppColors colors) async {
    final Color originalColor = _selectedAccent;
    Color currentColor = _selectedAccent;

    while (true) {
      if (!context.mounted) break;
      final Color? result = await showDialog<Color>(
        context: context,
        builder: (context) => CustomColorPickerDialog(initialColor: currentColor, colors: colors),
      );

      if (result == null) {
        ref.read(accentColorProvider.notifier).state = originalColor;
        break;
      }

      if (result.toARGB32() == 0) {
        if (!context.mounted) break;
        final Color? picked = await EyedropperHelper.pickColor(context);
        if (picked != null) {
          currentColor = picked;
          ref.read(accentColorProvider.notifier).state = picked;
        }
      } else {
        setState(() => _selectedAccent = result);
        ref.read(accentColorProvider.notifier).state = result;
        break;
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────
// CUSTOM COLOR PICKER DIALOG WIDGET (unchanged from original)
// ─────────────────────────────────────────────────────────────
class CustomColorPickerDialog extends ConsumerStatefulWidget {
  final Color initialColor;
  final AppColors colors;

  const CustomColorPickerDialog({super.key, required this.initialColor, required this.colors});

  @override
  ConsumerState<CustomColorPickerDialog> createState() => _CustomColorPickerDialogState();
}

class _CustomColorPickerDialogState extends ConsumerState<CustomColorPickerDialog> {
  late double _hue;
  late double _saturation;
  late double _value;
  late TextEditingController _hexController;
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
    final hsv = HSVColor.fromColor(_selectedColor);
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _value = hsv.value;
    final hexStr = _selectedColor.toARGB32().toRadixString(16).padLeft(8, '0');
    _hexController = TextEditingController(text: hexStr.substring(2).toUpperCase());
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _onSVChange(Offset localPos, double width, double height) {
    setState(() {
      _saturation = (localPos.dx / width).clamp(0.0, 1.0);
      _value = (1.0 - (localPos.dy / height)).clamp(0.0, 1.0);
      _selectedColor = HSVColor.fromAHSV(1.0, _hue, _saturation, _value).toColor();
      _hexController.text = _selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
    });
    ref.read(accentColorProvider.notifier).state = _selectedColor;
  }

  void _onHueChange(double newHue) {
    setState(() {
      _hue = newHue;
      _selectedColor = HSVColor.fromAHSV(1.0, _hue, _saturation, _value).toColor();
      _hexController.text = _selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
    });
    ref.read(accentColorProvider.notifier).state = _selectedColor;
  }

  void _onHexChange(String hex) {
    String cleanHex = hex.replaceAll('#', '');
    if (cleanHex.length == 6) {
      try {
        final color = Color(int.parse('FF$cleanHex', radix: 16));
        final hsv = HSVColor.fromColor(color);
        setState(() { _selectedColor = color; _hue = hsv.hue; _saturation = hsv.saturation; _value = hsv.value; });
        ref.read(accentColorProvider.notifier).state = _selectedColor;
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final isDark = _selectedColor.computeLuminance() < 0.5;

    return Dialog(
      backgroundColor: colors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Custom Accent Color', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colors.textPrimary)),
                IconButton(icon: const Icon(Icons.close), color: colors.textSecondary, onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                return SVBoxPicker(
                  hue: _hue, saturation: _saturation, value: _value,
                  onChange: (offset) => _onSVChange(offset, constraints.maxWidth, 180),
                );
              },
            ),
            const SizedBox(height: 16),
            HueSlider(hue: _hue, onChange: _onHueChange),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: _selectedColor, shape: BoxShape.circle, border: Border.all(color: colors.border))),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _hexController,
                    onChanged: _onHexChange,
                    style: TextStyle(color: colors.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      prefixText: '# ',
                      prefixStyle: TextStyle(color: colors.textSecondary, fontWeight: FontWeight.bold),
                      labelText: 'Hex Code',
                      labelStyle: TextStyle(color: colors.textSecondary),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: _selectedColor, width: 2)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(icon: const Icon(Icons.colorize_rounded), color: colors.textPrimary, tooltip: 'Pick from screen', onPressed: () => Navigator.pop(context, const Color(0x00000000))),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: colors.textSecondary))),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _selectedColor),
                  style: ElevatedButton.styleFrom(backgroundColor: _selectedColor, foregroundColor: isDark ? Colors.white : Colors.black),
                  child: const Text('Apply Accent'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SV BOX PICKER
// ─────────────────────────────────────────────────────────────
class SVBoxPicker extends StatelessWidget {
  final double hue;
  final double saturation;
  final double value;
  final ValueChanged<Offset> onChange;

  const SVBoxPicker({super.key, required this.hue, required this.saturation, required this.value, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (details) => onChange(details.localPosition),
      onPanUpdate: (details) => onChange(details.localPosition),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final cursorX = saturation * width;
          final cursorY = (1.0 - value) * height;

          return Container(
            height: 180,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white24)),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CustomPaint(painter: HSVColorPainter(hue)),
                  ),
                ),
                Positioned(
                  left: (cursorX - 8).clamp(-8.0, width - 8.0),
                  top: (cursorY - 8).clamp(-8.0, height - 8.0),
                  child: Container(
                    width: 16, height: 16,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 2)),
                      boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class HSVColorPainter extends CustomPainter {
  final double hue;
  HSVColorPainter(this.hue);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hsvColor = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
    final horizontalPaint = Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, 0), [Colors.white, hsvColor]);
    canvas.drawRect(rect, horizontalPaint);
    final verticalPaint = Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [Colors.transparent, Colors.black])
      ..blendMode = BlendMode.multiply;
    canvas.drawRect(rect, verticalPaint);
  }

  @override
  bool shouldRepaint(covariant HSVColorPainter oldDelegate) => oldDelegate.hue != hue;
}

// ─────────────────────────────────────────────────────────────
// HUE SLIDER
// ─────────────────────────────────────────────────────────────
class HueSlider extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChange;

  const HueSlider({super.key, required this.hue, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (details) => _updateHue(details.localPosition, context),
      onPanUpdate: (details) => _updateHue(details.localPosition, context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final cursorX = (hue / 360.0) * width;

          return Container(
            height: 20,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white24)),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CustomPaint(painter: HueSliderPainter()),
                  ),
                ),
                Positioned(
                  left: (cursorX - 6).clamp(-6.0, width - 6.0),
                  top: -2,
                  child: Container(
                    width: 12, height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: Colors.black26),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 2)],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _updateHue(Offset localPos, BuildContext context) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final double percent = (localPos.dx / box.size.width).clamp(0.0, 1.0);
    onChange(percent * 360.0);
  }
}

class HueSliderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const colors = [Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00), Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000)];
    final paint = Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, 0), colors);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
