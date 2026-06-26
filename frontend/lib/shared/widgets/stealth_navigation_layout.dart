import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../features/tutorial/providers/tutorial_provider.dart';
import '../../features/tutorial/screens/tutorial_overlay.dart';

/// Items in the workspace-scoped sidebar.
/// Only Chat, Sources, and Settings are full active items.
/// System Health is a utility link at the bottom.
enum StealthNavigationItem {
  chat,
  sources,
  settings,
  systemHealth,
}

class StealthNavigationLayout extends ConsumerWidget {
  final Widget child;
  final StealthNavigationItem activeItem;
  final String? workspaceId;
  final String? workspaceName;

  const StealthNavigationLayout({
    super.key,
    required this.child,
    required this.activeItem,
    this.workspaceId,
    this.workspaceName,
  });

  void _onItemTap(BuildContext context, StealthNavigationItem item) {
    if (activeItem == item) return;
    final id = workspaceId ?? 'default';

    switch (item) {
      case StealthNavigationItem.chat:
        context.go('/workspace/$id');
        break;
      case StealthNavigationItem.sources:
        context.push('/workspace/$id/upload');
        break;
      case StealthNavigationItem.settings:
        context.push('/workspace/$id/settings');
        break;
      case StealthNavigationItem.systemHealth:
        context.push('/system-health');
        break;
    }
  }

  Widget _buildNavItem({
    required BuildContext context,
    required StealthNavigationItem item,
    required IconData icon,
    required String label,
  }) {
    final colors = context.colors;
    final isSelected = activeItem == item;

    Key? widgetKey;
    if (item == StealthNavigationItem.sources) {
      widgetKey = TutorialKeys.addSources;
    } else if (item == StealthNavigationItem.settings) {
      widgetKey = TutorialKeys.settingsBtn;
    }

    return Padding(
      key: widgetKey,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: isSelected
            ? (Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF252525)
                : const Color(0xFFF1F1EF))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: () => _onItemTap(context, item),
          borderRadius: BorderRadius.circular(4),
          hoverColor: colors.textPrimary.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? colors.primary : colors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? colors.textPrimary : colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A greyed-out, non-tappable "coming soon" item.
  Widget _buildComingSoonItem({
    required BuildContext context,
    required IconData icon,
    required String label,
  }) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: colors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.textMuted,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF2D2D2D)
                    : const Color(0xFFEDEDEB),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'Soon',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: colors.textMuted,
                  fontFamily: 'IBM Plex Mono',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoneOverlay(BuildContext context, WidgetRef ref) {
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
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline_rounded, size: 36, color: Colors.green),
              ),
              const SizedBox(height: 16),
              Text(
                'You\'re All Set! 🎉',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'You have learned the basics of Kivo Workspace. Now you can ingest your local files and chat with them in complete privacy.',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => ref.read(tutorialProvider.notifier).finishTutorial(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Finish Tour', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayName = workspaceName ?? 'Workspace';
    final tutorialState = ref.watch(tutorialProvider);

    Widget layout = Scaffold(
      body: Row(
        children: [
          // Workspace-scoped left sidebar
          Container(
            width: 232,
            height: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F6F3),
              border: Border(
                right: BorderSide(color: colors.border, width: 1),
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- "All Workspaces" back button ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      child: InkWell(
                        onTap: () => context.go('/'),
                        borderRadius: BorderRadius.circular(4),
                        hoverColor: colors.textPrimary.withValues(alpha: 0.05),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          child: Row(
                            children: [
                              Icon(
                                Icons.arrow_back_rounded,
                                size: 14,
                                color: colors.textMuted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'All Workspaces',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: colors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // --- Workspace Name Header ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: colors.primary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'K',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                displayName,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Padding(
                          padding: const EdgeInsets.only(left: 26),
                          child: Text(
                            'v1.0.2-stealth',
                            style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'IBM Plex Mono',
                              color: colors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Divider
                  Divider(height: 1, color: colors.divider),
                  const SizedBox(height: 8),

                  // --- Core Navigation ---
                  _buildNavItem(
                    context: context,
                    item: StealthNavigationItem.chat,
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Chat',
                  ),
                  _buildNavItem(
                    context: context,
                    item: StealthNavigationItem.sources,
                    icon: Icons.folder_open_outlined,
                    label: 'Sources',
                  ),
                  _buildNavItem(
                    context: context,
                    item: StealthNavigationItem.settings,
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                  ),

                  const SizedBox(height: 16),

                  // --- Coming Soon section ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
                    child: Text(
                      'COMING SOON',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontFamily: 'IBM Plex Mono',
                        fontWeight: FontWeight.w600,
                        color: colors.textMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  _buildComingSoonItem(
                    context: context,
                    icon: Icons.extension_outlined,
                    label: 'Integrations',
                  ),
                  _buildComingSoonItem(
                    context: context,
                    icon: Icons.memory_outlined,
                    label: 'Models',
                  ),
                  _buildComingSoonItem(
                    context: context,
                    icon: Icons.list_alt_rounded,
                    label: 'Logs',
                  ),

                  const Spacer(),

                  // --- Bottom system utility ---
                  Divider(height: 1, color: colors.divider),
                  const SizedBox(height: 4),
                  _buildNavItem(
                    context: context,
                    item: StealthNavigationItem.systemHealth,
                    icon: Icons.settings_input_component_outlined,
                    label: 'System Health',
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // Main content area
          Expanded(child: child),
        ],
      ),
    );

    if (tutorialState.isActive) {
      if (tutorialState.currentStep == TutorialStep.addSources) {
        layout = TutorialOverlay(
          targetKey: TutorialKeys.addSources,
          title: 'Add Knowledge Sources',
          description: 'Upload PDFs, text files, images (OCR), or audio (transcription). All processing happens 100% locally on your machine.',
          onNext: () {
            ref.read(tutorialProvider.notifier).nextStep();
            context.go('/workspace/${workspaceId ?? 'default'}');
          },
          onSkip: () => ref.read(tutorialProvider.notifier).skipTutorial(),
          child: layout,
        );
      } else if (tutorialState.currentStep == TutorialStep.settings) {
        layout = TutorialOverlay(
          targetKey: TutorialKeys.settingsBtn,
          title: 'Workspace Settings',
          description: 'Tweak retrieval options, configure your local LLM model temperature, or change themes and typography here.',
          onNext: () {
            ref.read(tutorialProvider.notifier).nextStep();
          },
          onSkip: () => ref.read(tutorialProvider.notifier).skipTutorial(),
          child: layout,
        );
      } else if (tutorialState.currentStep == TutorialStep.done) {
        layout = Stack(
          children: [
            layout,
            _buildDoneOverlay(context, ref),
          ],
        );
      }
    }

    return layout;
  }
}
