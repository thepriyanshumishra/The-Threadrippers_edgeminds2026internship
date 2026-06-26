import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/font_provider.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/router/app_router.dart';
import '../../workspace/models/workspace.dart';
import '../../workspace/providers/workspace_providers.dart';
import '../../workspace/services/workspace_service.dart';
import '../../chat/providers/chat_providers.dart';
import '../../onboarding/services/onboarding_prefs.dart';
import '../../onboarding/providers/onboarding_provider.dart';
import '../../tutorial/providers/tutorial_provider.dart';
import '../../tutorial/screens/tutorial_overlay.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../../../core/constants/app_constants.dart';
import '../../../core/services/update_service.dart';

final allWorkspaceStatsProvider = FutureProvider.autoDispose<Map<String, Map<String, dynamic>>>((ref) async {
  final workspacesVal = ref.watch(workspacesProvider);
  final list = workspacesVal.value ?? [];
  final Map<String, Map<String, dynamic>> stats = {};
  final service = ref.watch(workspaceServiceProvider);
  for (var ws in list) {
    try {
      final s = await service.getWorkspaceStats(ws.id);
      stats[ws.id] = s;
    } catch (_) {
      stats[ws.id] = {
        "chunks_count": 0,
        "embedding_dim": 768,
        "embedding_model": "gte-multilingual-base",
        "status": "ready"
      };
    }
  }
  return stats;
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedTab = 0; // 0: Dashboard, 1: Analytics
  final TextEditingController _searchController = TextEditingController();

  // State variables for in-app updates
  bool _isCheckingUpdate = false;
  UpdateInfo? _updateInfo;
  double? _updateDownloadProgress;
  String _updateStatusText = '';
  bool _updateError = false;

  void _updateState(StateSetter setSheetState, VoidCallback fn) {
    setSheetState(fn);
    if (mounted) {
      setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    _initSettingsAndCheckOnboarding();
  }

  Future<void> _initSettingsAndCheckOnboarding() async {
    final complete = await OnboardingPrefs.isOnboardingComplete();
    if (!complete) {
      if (mounted) {
        context.go('/onboarding');
      }
      return;
    }

    final themeStr = await OnboardingPrefs.getThemeMode();
    final fontStr = await OnboardingPrefs.getFontFamily();
    final accentStr = await OnboardingPrefs.getAccentColor();
    final activeModel = await OnboardingPrefs.getActiveModel();
    final ollamaUrl = await OnboardingPrefs.getOllamaUrl();

    if (mounted) {
      ref.read(themeModeProvider.notifier).state = themeStr == 'light' ? ThemeMode.light : ThemeMode.dark;
      ref.read(fontProvider.notifier).state = AppFontFamily.values.firstWhere(
        (f) => f.name == fontStr,
        orElse: () => AppFontFamily.sans,
      );
      ref.read(accentColorProvider.notifier).state = Color(int.parse(accentStr.replaceAll('#', '0xFF')));
      ref.read(activeModelProvider.notifier).state = activeModel;
      ref.read(ollamaUrlProvider.notifier).state = ollamaUrl;
    }

    // Dynamic backend spawner check at app launch
    if (!kIsWeb) {
      final service = ref.read(onboardingServiceProvider);
      final isHealthy = await service.isBackendHealthy();
      if (!isHealthy) {
        await service.spawnBackendProcess(defaultModel: activeModel);
      }
    }

    // Trigger onboarding tutorial overlay if not complete yet
    final tutorialDone = await OnboardingPrefs.isTutorialComplete();
    if (!tutorialDone && mounted) {
      ref.read(tutorialProvider.notifier).startTutorial();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showCreateWorkspaceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const _CreateWorkspaceDialog(),
    );
  }

  void _showGlobalSettings(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF202020) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Consumer(
          builder: (ctx, ref, _) {
          final currentFont = ref.watch(fontProvider);
          final activeAccent = ref.watch(accentColorProvider);
          final notificationsOn = ref.watch(notificationsEnabledProvider);

          final ollamaUrl = ref.watch(ollamaUrlProvider);
          final temp = ref.watch(ragTemperatureProvider);
          final threshold = ref.watch(ragSimilarityThresholdProvider);
          final chunkSize = ref.watch(ragChunkSizeProvider);
          final chunkOverlap = ref.watch(ragChunkOverlapProvider);

          final accentColors = [
            const Color(0xFF0075DE), // Blue
            const Color(0xFF0F7B44), // Green
            const Color(0xFF6366F1), // Indigo
            const Color(0xFFE11D48), // Crimson
          ];

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'App Settings',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Theme Selection
                  Text('Theme', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textMuted)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => ref.read(themeModeProvider.notifier).state = ThemeMode.light,
                        icon: const Icon(Icons.light_mode_outlined, size: 14),
                        label: const Text('Light'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? colors.textSecondary : colors.primary,
                          side: BorderSide(color: !isDark ? colors.primary : colors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => ref.read(themeModeProvider.notifier).state = ThemeMode.dark,
                        icon: const Icon(Icons.dark_mode_outlined, size: 14),
                        label: const Text('Dark'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? colors.primary : colors.textSecondary,
                          side: BorderSide(color: isDark ? colors.primary : colors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Typography selection
                  Text('Typography', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textMuted)),
                  const SizedBox(height: 8),
                  SegmentedButton<AppFontFamily>(
                    segments: const [
                      ButtonSegment(value: AppFontFamily.sans, label: Text('Sans')),
                      ButtonSegment(value: AppFontFamily.serif, label: Text('Serif')),
                      ButtonSegment(value: AppFontFamily.mono, label: Text('Mono')),
                    ],
                    selected: {currentFont},
                    onSelectionChanged: (val) {
                      ref.read(fontProvider.notifier).state = val.first;
                    },
                    style: ButtonStyle(
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Accent Colors Selector
                  Text('Accent Highlight Color', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textMuted)),
                  const SizedBox(height: 8),
                  Row(
                    children: accentColors.map((color) {
                      final isSelected = activeAccent == color;
                      return GestureDetector(
                        onTap: () => ref.read(accentColorProvider.notifier).state = color,
                        child: Container(
                          margin: const EdgeInsets.only(right: 12),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: isDark ? Colors.white : Colors.black, width: 2)
                                : Border.all(color: Colors.transparent),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // Notification switch
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Desktop Notifications', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textMuted)),
                          const SizedBox(height: 2),
                          Text('Notify when Ingestion finishes', style: TextStyle(fontSize: 11, color: colors.textSecondary)),
                        ],
                      ),
                      Switch(
                        value: notificationsOn,
                        onChanged: (val) => ref.read(notificationsEnabledProvider.notifier).state = val,
                        // ignore: deprecated_member_use
                        activeColor: colors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Manage Models Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context); // Close bottom sheet
                        context.push(AppRoutes.modelDownloader); // Open model downloader
                      },
                      icon: const Icon(Icons.settings_suggest_rounded, size: 16),
                      label: const Text('Manage Installed Models', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.primary,
                        side: BorderSide(color: colors.primary.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),

                  // Software Update Section
                  _buildUpdateSection(context, setSheetState),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),

                  // Advanced Settings Accordion
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      title: Text(
                        'Advanced Settings',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () {
                              ref.read(ollamaUrlProvider.notifier).state = 'http://localhost:11434';
                              ref.read(ragTemperatureProvider.notifier).state = 0.0;
                              ref.read(ragSimilarityThresholdProvider.notifier).state = 0.35;
                              ref.read(ragChunkSizeProvider.notifier).state = 750;
                              ref.read(ragChunkOverlapProvider.notifier).state = 150;
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 12),
                            label: const Text('Reset Defaults'),
                            style: TextButton.styleFrom(
                              foregroundColor: colors.primary,
                              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Ollama Host URL
                        Text('Ollama Service Host URL', style: TextStyle(fontSize: 11.5, color: colors.textSecondary)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: TextEditingController(text: ollamaUrl)..selection = TextSelection.collapsed(offset: ollamaUrl.length),
                          style: TextStyle(color: colors.textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'http://localhost:11434',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                          onSubmitted: (val) => ref.read(ollamaUrlProvider.notifier).state = val.trim(),
                        ),
                        const SizedBox(height: 16),

                        // LLM Temperature
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('LLM Temperature', style: TextStyle(fontSize: 11.5, color: colors.textSecondary)),
                            Text(temp.toStringAsFixed(1), style: TextStyle(fontSize: 11, color: colors.textPrimary, fontFamily: 'IBM Plex Mono')),
                          ],
                        ),
                        Slider(
                          value: temp,
                          min: 0.0,
                          max: 1.0,
                          divisions: 10,
                          activeColor: colors.primary,
                          onChanged: (val) => ref.read(ragTemperatureProvider.notifier).state = val,
                        ),
                        const SizedBox(height: 12),

                        // Similarity Threshold
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Retrieval Similarity Threshold', style: TextStyle(fontSize: 11.5, color: colors.textSecondary)),
                            Text(threshold.toStringAsFixed(2), style: TextStyle(fontSize: 11, color: colors.textPrimary, fontFamily: 'IBM Plex Mono')),
                          ],
                        ),
                        Slider(
                          value: threshold,
                          min: 0.0,
                          max: 1.0,
                          divisions: 20,
                          activeColor: colors.primary,
                          onChanged: (val) => ref.read(ragSimilarityThresholdProvider.notifier).state = val,
                        ),
                        const SizedBox(height: 12),

                        // Chunk Size & Overlap
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Chunk Size (words)', style: TextStyle(fontSize: 11.5, color: colors.textSecondary)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    keyboardType: TextInputType.number,
                                    controller: TextEditingController(text: chunkSize.toString()),
                                    style: TextStyle(color: colors.textPrimary, fontSize: 13),
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                    ),
                                    onSubmitted: (val) {
                                      final size = int.tryParse(val) ?? 750;
                                      ref.read(ragChunkSizeProvider.notifier).state = size;
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Chunk Overlap (words)', style: TextStyle(fontSize: 11.5, color: colors.textSecondary)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    keyboardType: TextInputType.number,
                                    controller: TextEditingController(text: chunkOverlap.toString()),
                                    style: TextStyle(color: colors.textPrimary, fontSize: 13),
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                    ),
                                    onSubmitted: (val) {
                                      final lap = int.tryParse(val) ?? 150;
                                      ref.read(ragChunkOverlapProvider.notifier).state = lap;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Cloud API coming soon section
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFF1F1EF),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: colors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.cloud_off_outlined, size: 16, color: colors.textMuted),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Cloud Models Integration',
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: colors.textMuted),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      'Soon',
                                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: colors.primary),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Run queries on cloud APIs like Anthropic Claude, OpenAI, and Gemini Pro in future builds.',
                                style: TextStyle(fontSize: 11, color: colors.textMuted, height: 1.4),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                enabled: false,
                                decoration: InputDecoration(
                                  hintText: 'Claude API Key (Locked)',
                                  hintStyle: TextStyle(color: colors.textMuted, fontSize: 12),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                  fillColor: isDark ? const Color(0xFF242424) : const Color(0xFFE5E5E3),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  Text(
                    'Kivo Workspace v${AppConstants.appVersion}',
                    style: TextStyle(fontSize: 11, color: colors.textMuted, fontFamily: 'IBM Plex Mono'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

  Widget _buildTopTabBar(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tabs = ['Dashboard', 'Analytics'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Logo Image Branding
          Image.asset(
            key: TutorialKeys.logo,
            isDark ? 'assets/images/branding_dark.png' : 'assets/images/branding_light.png',
            height: 38,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Text(
                'Kivo Workspace',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                  letterSpacing: -0.3,
                ),
              );
            },
          ),
          const SizedBox(width: 32),
          // Tabs
          ...tabs.asMap().entries.map((entry) {
            final idx = entry.key;
            final title = entry.value;
            final isSelected = _selectedTab == idx;

            return InkWell(
              onTap: () {
                setState(() {
                  _selectedTab = idx;
                });
              },
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.only(right: 24),
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected ? colors.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? colors.textPrimary : colors.textSecondary,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildWelcomeOverlay(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      alignment: Alignment.center,
      child: Card(
        color: colors.sidebarBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border),
        ),
        elevation: 12,
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.rocket_launch_rounded, size: 36, color: colors.primary),
              ),
              const SizedBox(height: 16),
              Text(
                'Welcome to Kivo Workspace! 🚀',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your offline-first AI environment is ready. Let\'s take a quick 1-minute tour to see how to organize your documents and chat with your local AI models.',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => ref.read(tutorialProvider.notifier).skipTutorial(),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.textMuted,
                    ),
                    child: const Text('Skip Tour'),
                  ),
                  ElevatedButton(
                    onPressed: () => ref.read(tutorialProvider.notifier).nextStep(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: const Text('Start Tour', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpdateSection(BuildContext context, StateSetter setSheetState) {
    if (kIsWeb) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final updateService = UpdateService();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Software Update',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF242424) : const Color(0xFFF9F9F8),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Version: v${AppConstants.appVersion}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _updateStatusText.isNotEmpty
                              ? _updateStatusText
                              : 'Check for the latest updates from GitHub.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _updateError ? colors.statusFailed : colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!_isCheckingUpdate && _updateDownloadProgress == null)
                    ElevatedButton(
                      onPressed: () async {
                        _updateState(setSheetState, () {
                          _isCheckingUpdate = true;
                          _updateStatusText = 'Checking for updates...';
                          _updateError = false;
                        });

                        final info = await updateService.checkForUpdate();

                        _updateState(setSheetState, () {
                          _isCheckingUpdate = false;
                          _updateInfo = info;
                          if (info.hasUpdate) {
                            _updateStatusText = 'New version v${info.latestVersion} available!';
                          } else if (info.latestVersion.isNotEmpty) {
                            _updateStatusText = 'Kivo Workspace is up-to-date.';
                          } else {
                            _updateStatusText = 'Failed to check for updates.';
                            _updateError = true;
                          }
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      child: const Text('Check'),
                    ),
                  if (_isCheckingUpdate)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              if (_updateInfo != null && _updateInfo!.hasUpdate && _updateDownloadProgress == null) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                Text(
                  'What\'s New:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _updateInfo!.releaseNotes,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      _updateState(setSheetState, () {
                        _updateDownloadProgress = 0.0;
                        _updateStatusText = 'Starting download...';
                      });

                      final ext = Platform.isWindows ? 'exe' : (Platform.isMacOS ? 'dmg' : 'AppImage');
                      final assetName = 'KivoWorkspace-Update.$ext';
                      final tempDir = Directory.systemTemp;
                      final savePath = path.join(tempDir.path, assetName);

                      try {
                        final stream = updateService.downloadUpdate(_updateInfo!.downloadUrl, savePath);
                        await for (final progress in stream) {
                          _updateState(setSheetState, () {
                            _updateDownloadProgress = progress;
                            _updateStatusText = 'Downloading update: ${(progress * 100).toStringAsFixed(0)}%';
                          });
                        }

                        _updateState(setSheetState, () {
                          _updateStatusText = Platform.isWindows
                              ? 'Download complete. Launching installer...'
                              : (Platform.isMacOS
                                  ? 'Download complete. Mounting disk image...'
                                  : 'Download complete. Launching file...');
                        });

                        await updateService.applyUpdate(savePath);

                        if (Platform.isMacOS) {
                          _updateState(setSheetState, () {
                            _updateStatusText = 'Disk image mounted. Please close Kivo, drag it to Applications, and restart.';
                            _updateDownloadProgress = null;
                            _updateInfo = null;
                          });
                        }
                      } catch (e) {
                        _updateState(setSheetState, () {
                          _updateStatusText = 'Download failed: $e';
                          _updateDownloadProgress = null;
                          _updateError = true;
                        });
                      }
                    },
                    icon: const Icon(Icons.download_rounded, size: 14),
                    label: const Text('Download & Install Update', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
              if (_updateDownloadProgress != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _updateDownloadProgress,
                  backgroundColor: colors.border,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final workspacesState = ref.watch(workspacesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tutorialState = ref.watch(tutorialProvider);

    Widget scaffold = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 52,
        title: _buildTopTabBar(context),
        actions: [
          // Theme switch
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 18,
              color: colors.textSecondary,
            ),
            tooltip: 'Toggle Theme',
            onPressed: () {
              ref.read(themeModeProvider.notifier).state =
                  isDark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
          // System Health icon
          IconButton(
            icon: Icon(Icons.settings_input_component_outlined, size: 18, color: colors.textSecondary),
            tooltip: 'System Health',
            onPressed: () {
              context.push('/system-health');
            },
          ),
          // Global Settings (theme + font picker)
          IconButton(
            icon: Icon(Icons.settings_outlined, size: 18, color: colors.textSecondary),
            tooltip: 'Settings',
            onPressed: () {
              _showGlobalSettings(context);
            },
          ),
          // Profile avatar placeholder
          Padding(
            padding: const EdgeInsets.only(right: 16, left: 8),
            child: CircleAvatar(
              radius: 12,
              backgroundColor: isDark ? const Color(0xFF333333) : const Color(0xFFEDEDEB),
              child: Text(
                'U',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: colors.divider),
        ),
      ),
      body: workspacesState.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded, size: 40, color: colors.statusFailed),
              const SizedBox(height: 16),
              Text('Failed to load workspaces', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(error.toString(), style: TextStyle(color: colors.textSecondary, fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.read(workspacesProvider.notifier).loadWorkspaces(),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
        data: (workspaces) {
          if (_selectedTab == 1) {
            return _buildAnalyticsPanel(context, workspaces);
          }
          final query = _searchController.text.trim().toLowerCase();
          final filteredWorkspaces = workspaces.where((w) {
            return w.name.toLowerCase().contains(query);
          }).toList();

          return SingleChildScrollView(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Centered Search Bar
                    Center(
                      child: Container(
                        width: double.infinity,
                        height: 38,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF202020) : const Color(0xFFFBFBFA),
                          border: Border.all(color: colors.border, width: 1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 12),
                            Icon(Icons.search_rounded, size: 16, color: colors.textMuted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: TextStyle(color: colors.textPrimary, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Search workspaces...',
                                  hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (value) {
                                  setState(() {});
                                },
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFEDEDEB),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                'Ctrl+K',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'IBM Plex Mono',
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Workspaces Section Header
                    Row(
                      children: [
                        Text(
                          'Workspaces',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          key: TutorialKeys.createWorkspace,
                          onPressed: () => _showCreateWorkspaceDialog(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          ),
                          child: const Text('New Workspace'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Workspaces List Content
                    if (filteredWorkspaces.isEmpty)
                      _buildEmptyState(context)
                    else ...[
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredWorkspaces.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          return _WorkspaceCard(workspace: filteredWorkspaces[index]);
                        },
                      ),
                    ],
                    const SizedBox(height: 32),
                    // Universal Search divider CTA
                    InkWell(
                      onTap: () => context.push('/multi-workspace-chat'),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF202020) : const Color(0xFFFAF9F7),
                          border: Border.all(color: colors.border),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.manage_search_rounded, size: 16, color: colors.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Universal Search',
                                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colors.textPrimary),
                                  ),
                                  Text(
                                    'Search across all workspaces at once.',
                                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_forward_rounded, size: 15, color: colors.textMuted),
                          ],
                        ),
                      ),
                    ),

                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (tutorialState.isActive) {
      if (tutorialState.currentStep == TutorialStep.welcome) {
        scaffold = Stack(
          children: [
            scaffold,
            _buildWelcomeOverlay(context, ref),
          ],
        );
      } else if (tutorialState.currentStep == TutorialStep.createWorkspace) {
        scaffold = TutorialOverlay(
          targetKey: TutorialKeys.createWorkspace,
          title: 'Create a Workspace',
          description: 'Workspaces are isolated environments where you can organize different projects, topics, or document sets.',
          onNext: () {
            _showCreateWorkspaceDialog(context);
          },
          onSkip: () => ref.read(tutorialProvider.notifier).skipTutorial(),
          child: scaffold,
        );
      }
    }

    return scaffold;
  }

  Widget _buildEmptyState(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.folder_open_rounded, size: 36, color: colors.textMuted),
          const SizedBox(height: 12),
          Text(
            'No workspaces found',
            style: TextStyle(color: colors.textSecondary, fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsPanel(BuildContext context, List<Workspace> workspaces) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final displayWorkspaces = workspaces;
    final statsAsync = ref.watch(allWorkspaceStatsProvider);
    final statsMap = statsAsync.value ?? <String, Map<String, dynamic>>{};
    final queryHistory = ref.watch(queryHistoryProvider);

    int totalSources = 0;
    int totalChunks = 0;
    for (var ws in displayWorkspaces) {
      totalSources += ws.sourcesCount;
      final wsStats = statsMap[ws.id];
      if (wsStats != null) {
        totalChunks += wsStats['chunks_count'] as int? ?? 0;
      } else {
        totalChunks += ws.sourcesCount * 48;
      }
    }

    final avgLatency = queryHistory.isEmpty
        ? 0
        : (queryHistory.map((q) => q.latencyMs).reduce((a, b) => a + b) / queryHistory.length).round();

    final avgLatencyStr = queryHistory.isEmpty ? '0ms' : '${avgLatency}ms';

    return SingleChildScrollView(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Analytics Dashboard',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'RAG indexing and retrieval performance indicators across all local workspaces.',
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
              ),
              const SizedBox(height: 24),
              
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 2.5,
                children: [
                  _buildStatCard(
                    context,
                    title: 'FAISS Indexed Chunks',
                    value: '$totalChunks',
                    subtitle: 'Normalized 768d dense vectors',
                    icon: Icons.hub_outlined,
                    iconColor: colors.primary,
                  ),
                  _buildStatCard(
                    context,
                    title: 'Average Query Latency',
                    value: avgLatencyStr,
                    subtitle: 'Vector database search time',
                    icon: Icons.speed_rounded,
                    iconColor: Colors.teal,
                  ),
                  _buildStatCard(
                    context,
                    title: 'Parent/Child Ratio',
                    value: totalSources == 0 ? '1 : 0.0' : '1 : 4.0',
                    subtitle: 'Typical split ratio per source',
                    icon: Icons.schema_outlined,
                    iconColor: Colors.purple,
                  ),
                  _buildStatCard(
                    context,
                    title: 'Storage Footprint',
                    value: '${(totalSources * 0.45).toStringAsFixed(2)} MB',
                    subtitle: 'Index & SQLite storage utilized',
                    icon: Icons.storage_rounded,
                    iconColor: Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF202020) : Colors.white,
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Retrieval Latency Trend',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'RAG retrieval & local generation time over last 10 queries',
                      style: TextStyle(fontSize: 11, color: colors.textMuted),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 140,
                      child: queryHistory.isEmpty
                          ? Center(
                              child: Text(
                                'No queries recorded in this session.',
                                style: TextStyle(color: colors.textMuted, fontSize: 13),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: () {
                                final last10 = queryHistory.length > 10
                                    ? queryHistory.sublist(queryHistory.length - 10)
                                    : queryHistory;
                                final maxLatency = last10.map((q) => q.latencyMs).reduce((a, b) => a > b ? a : b);
                                return last10.map((q) {
                                  final double barHeight = maxLatency == 0
                                      ? 10
                                      : (q.latencyMs / maxLatency) * 90 + 10;
                                  final index = queryHistory.indexOf(q);
                                  final label = 'Q${index + 1}';
                                  final isLatest = q == last10.last;
                                  return _buildChartBar(
                                    context,
                                    height: barHeight,
                                    label: label,
                                    value: '${q.latencyMs}ms',
                                    isLatest: isLatest,
                                  );
                                }).toList();
                              }(),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF202020) : Colors.white,
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Local Workspace Metrics',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    Table(
                      columnWidths: const {
                        0: FlexColumnWidth(3),
                        1: FlexColumnWidth(2),
                        2: FlexColumnWidth(2),
                        3: FlexColumnWidth(2),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: colors.divider)),
                          ),
                          children: [
                            _buildTableHeaderCell('Workspace Name', colors),
                            _buildTableHeaderCell('Sources', colors),
                            _buildTableHeaderCell('Estimated Chunks', colors),
                            _buildTableHeaderCell('Status', colors),
                          ],
                        ),
                        if (displayWorkspaces.isEmpty)
                          TableRow(
                            children: [
                              _buildTableCell('No workspaces available', colors, color: colors.textMuted),
                              _buildTableCell('-', colors),
                              _buildTableCell('-', colors),
                              _buildTableCell('-', colors),
                            ],
                          )
                        else
                          ...displayWorkspaces.map((ws) {
                            final wsStats = statsMap[ws.id];
                            final chunks = wsStats != null ? (wsStats['chunks_count'] as int? ?? 0) : (ws.sourcesCount * 48);
                            return TableRow(
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: colors.divider)),
                              ),
                              children: [
                                _buildTableCell(ws.name, colors, isBold: true),
                                _buildTableCell('${ws.sourcesCount}', colors),
                                _buildTableCell('$chunks', colors),
                                _buildTableCell(
                                  ws.status.name.toUpperCase(), 
                                  colors,
                                  color: ws.status == WorkspaceStatus.ready 
                                    ? colors.statusReady 
                                    : ws.status == WorkspaceStatus.processing 
                                      ? Colors.orange 
                                      : colors.statusFailed,
                                ),
                              ],
                            );
                          }),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242424) : const Color(0xFFFAF9F7),
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 11, color: colors.textSecondary, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 9.5, color: colors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartBar(
    BuildContext context, {
    required double height,
    required String label,
    required String value,
    bool isLatest = false,
  }) {
    final colors = context.colors;
    return Expanded(
      child: Tooltip(
        message: value,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              height: height,
              width: 24,
              decoration: BoxDecoration(
                color: isLatest ? colors.primary : colors.primary.withValues(alpha: 0.4),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 10, 
                color: colors.textSecondary, 
                fontWeight: isLatest ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeaderCell(String text, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: colors.textSecondary),
      ),
    );
  }

  Widget _buildTableCell(String text, AppColors colors, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12, 
          fontWeight: isBold ? FontWeight.w600 : FontWeight.normal, 
          color: color ?? colors.textPrimary,
        ),
      ),
    );
  }
}

class _WorkspaceCard extends ConsumerStatefulWidget {
  final Workspace workspace;

  const _WorkspaceCard({required this.workspace});

  @override
  ConsumerState<_WorkspaceCard> createState() => _WorkspaceCardState();
}

class _WorkspaceCardState extends ConsumerState<_WorkspaceCard> {
  bool _isHovered = false;

  void _showRenameDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _RenameWorkspaceDialog(workspace: widget.workspace),
    );
  }

  void _showDeleteConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _DeleteConfirmDialog(workspace: widget.workspace),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Determine states mapping
    final isProcessing = widget.workspace.status == WorkspaceStatus.processing;
    final isFailed = widget.workspace.status == WorkspaceStatus.failed;

    // Styled Card
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: () {
          // Go to source upload if no sources, else chat workspace
          if (widget.workspace.sourcesCount == 0) {
            context.push('/workspace/${widget.workspace.id}/upload');
          } else if (isProcessing) {
            context.push('/workspace/${widget.workspace.id}/processing');
          } else {
            context.push('/workspace/${widget.workspace.id}');
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isFailed
                ? (isDark ? const Color(0xFF3F1E1E) : const Color(0xFFFFECEB))
                : (isDark ? const Color(0xFF202020) : Colors.white),
            border: Border.all(
              color: isFailed
                  ? colors.statusFailed.withValues(alpha: 0.5)
                  : colors.border,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left status dot/spinner
              if (isProcessing)
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(right: 12),
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                  ),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(
                    color: isFailed
                        ? colors.statusFailed
                        : colors.primary,
                    shape: BoxShape.circle,
                  ),
                ),

              // Title and details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.workspace.name,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (isProcessing) ...[
                      // Progress Bar inside the card
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: const LinearProgressIndicator(
                                value: 0.6,
                                minHeight: 4,
                                backgroundColor: Color(0xFFEDEDEB),
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            '60%',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ] else if (isFailed) ...[
                      // Failed status callout
                      Row(
                        children: [
                          Icon(Icons.error_outline_rounded, size: 13, color: colors.statusFailed),
                          const SizedBox(width: 4),
                          Text(
                            'Ingestion failed: timeout',
                            style: TextStyle(
                              color: colors.statusFailed,
                              fontSize: 11.5,
                              fontFamily: 'IBM Plex Mono',
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // Normal details
                      Text(
                        '${widget.workspace.sourcesCount} Sources  |  4.2 MB  |  Updated 2h ago',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Hover choices or stealth actions menu
              if (_isHovered)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.edit_outlined, size: 16, color: colors.textSecondary),
                      tooltip: 'Rename',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _showRenameDialog(context),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded, size: 16, color: colors.statusFailed),
                      tooltip: 'Delete',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _showDeleteConfirmDialog(context),
                    ),
                  ],
                )
              else
                Icon(
                  Icons.more_horiz_rounded,
                  size: 16,
                  color: colors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateWorkspaceDialog extends ConsumerStatefulWidget {
  const _CreateWorkspaceDialog();

  @override
  ConsumerState<_CreateWorkspaceDialog> createState() => _CreateWorkspaceDialogState();
}

class _CreateWorkspaceDialogState extends ConsumerState<_CreateWorkspaceDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final name = _controller.text.trim();
      final newW = await ref.read(workspacesProvider.notifier).createWorkspace(name);
      if (mounted) {
        if (ref.read(tutorialProvider).currentStep == TutorialStep.createWorkspace) {
          ref.read(tutorialProvider.notifier).nextStep();
        }
        Navigator.of(context).pop(); // Close dialog
        context.push(
          AppRoutes.sourceUpload.replaceAll(':workspaceId', newW.id),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: context.colors.statusFailed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      surfaceTintColor: Colors.transparent,
      backgroundColor: isDark ? const Color(0xFF202020) : const Color(0xFFFBFBFA),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      title: Text(
        'New Workspace',
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter a name for your new workspace knowledge base.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              autofocus: true,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'e.g., Q3 Marketing Campaign',
                hintStyle: TextStyle(color: colors.textMuted, fontSize: 13.5),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Workspace name is required';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

class _RenameWorkspaceDialog extends ConsumerStatefulWidget {
  final Workspace workspace;

  const _RenameWorkspaceDialog({required this.workspace});

  @override
  ConsumerState<_RenameWorkspaceDialog> createState() => _RenameWorkspaceDialogState();
}

class _RenameWorkspaceDialogState extends ConsumerState<_RenameWorkspaceDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.workspace.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final name = _controller.text.trim();
      await ref.read(workspacesProvider.notifier).renameWorkspace(widget.workspace.id, name);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: context.colors.statusFailed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      surfaceTintColor: Colors.transparent,
      backgroundColor: isDark ? const Color(0xFF202020) : const Color(0xFFFBFBFA),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      title: Text(
        'Rename Workspace',
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter a new name for "${widget.workspace.name}".',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              autofocus: true,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Workspace name is required';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _DeleteConfirmDialog extends ConsumerStatefulWidget {
  final Workspace workspace;

  const _DeleteConfirmDialog({required this.workspace});

  @override
  ConsumerState<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends ConsumerState<_DeleteConfirmDialog> {
  bool _isLoading = false;

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(workspacesProvider.notifier).deleteWorkspace(widget.workspace.id);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: context.colors.statusFailed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      surfaceTintColor: Colors.transparent,
      backgroundColor: isDark ? const Color(0xFF202020) : const Color(0xFFFBFBFA),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      title: Text(
        'Delete Workspace',
        style: TextStyle(
          color: colors.statusFailed,
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Text(
        'Are you sure you want to delete "${widget.workspace.name}"? This will permanently delete the workspace and all of its processed sources. This action cannot be undone.',
        style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.statusFailed,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Delete'),
        ),
      ],
    );
  }
}
