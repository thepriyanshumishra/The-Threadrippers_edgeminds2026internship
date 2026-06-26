import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/stealth_navigation_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/workspace_providers.dart';

class WorkspaceSettingsScreen extends ConsumerStatefulWidget {
  final String workspaceId;

  const WorkspaceSettingsScreen({super.key, required this.workspaceId});

  @override
  ConsumerState<WorkspaceSettingsScreen> createState() => _WorkspaceSettingsScreenState();
}

class _WorkspaceSettingsScreenState extends ConsumerState<WorkspaceSettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _instructionsController;
  bool _isSaving = false;
  bool _isInitialized = false;
  final Set<String> _selectedPresets = {};

  final String _baseInstructions =
      'You are a helpful assistant. Base your answers strictly on the provided context.\n'
      'Do not assume facts or make up information not present in the workspace files.';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _instructionsController = TextEditingController();
    _instructionsController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _instructionsController.removeListener(_onTextChanged);
    _instructionsController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  String _buildInstructionsText() {
    final buffer = StringBuffer(_baseInstructions);
    if (_selectedPresets.contains('Bullet Points Only')) {
      buffer.write('\n\nFormat the output using clear bullet points only.');
    }
    if (_selectedPresets.contains('Explain Simply')) {
      buffer.write('\n\nExplain concepts in a simple, easy-to-understand manner.');
    }
    if (_selectedPresets.contains('Answer in Hindi')) {
      buffer.write('\n\nRespond in Hindi (Devanagari script) whenever possible.');
    }
    buffer.write('\n\nAvoid generic pleasantries. Be concise and direct.');
    return buffer.toString();
  }

  void _togglePreset(String preset) {
    setState(() {
      if (_selectedPresets.contains(preset)) {
        _selectedPresets.remove(preset);
      } else {
        _selectedPresets.add(preset);
      }
      _instructionsController.text = _buildInstructionsText();
    });
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
    });

    try {
      final name = _nameController.text.trim();
      final instructions = _instructionsController.text.trim();

      if (name.isEmpty) {
        throw Exception('Workspace name cannot be empty');
      }

      await ref.read(workspacesProvider.notifier).updateWorkspaceSettings(
            widget.workspaceId,
            name: name,
            instructions: instructions,
          );

      // Reload both active workspace details and stats
      ref.invalidate(activeWorkspaceProvider(widget.workspaceId));
      ref.invalidate(workspaceStatsProvider(widget.workspaceId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Workspace settings saved successfully.',
              style: TextStyle(fontSize: 13),
            ),
            backgroundColor: context.colors.statusReady,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to save workspace settings: $e',
              style: const TextStyle(fontSize: 13),
            ),
            backgroundColor: context.colors.statusFailed,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final workspaceAsync = ref.watch(activeWorkspaceProvider(widget.workspaceId));
    final statsAsync = ref.watch(workspaceStatsProvider(widget.workspaceId));

    // Initialize text form controllers once workspace data is loaded
    workspaceAsync.whenData((workspace) {
      if (!_isInitialized) {
        _nameController.text = workspace.name;
        _instructionsController.text = workspace.instructions.isNotEmpty
            ? workspace.instructions
            : _baseInstructions;

        // Auto-select presets based on loaded instructions content
        final text = _instructionsController.text.toLowerCase();
        if (text.contains('bullet points')) {
          _selectedPresets.add('Bullet Points Only');
        }
        if (text.contains('simple') || text.contains('easy-to-understand')) {
          _selectedPresets.add('Explain Simply');
        }
        if (text.contains('hindi') || text.contains('हिंदी')) {
          _selectedPresets.add('Answer in Hindi');
        }

        _isInitialized = true;
      }
    });

    final workspaceName = workspaceAsync.maybeWhen(
      data: (w) => w.name,
      orElse: () => 'Settings',
    );

    final lines = _instructionsController.text.split('\n');
    final lineCount = lines.isEmpty ? 1 : lines.length;

    return StealthNavigationLayout(
      activeItem: StealthNavigationItem.settings,
      workspaceId: widget.workspaceId,
      workspaceName: workspaceName,
      child: Scaffold(
        backgroundColor: colors.background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 750;

              return Column(
                children: [
                  // Top Editor Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: colors.border)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Instructions Editor',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Define system prompts for this workspace context.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveSettings,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_outlined, size: 14),
                          label: Text(_isSaving ? 'Saving...' : 'Save'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: colors.primary.withValues(alpha: 0.6),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Main Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: isWide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Left Column (Metrics / Models) - width 280
                                    SizedBox(
                                      width: 280,
                                      child: _buildLeftPanel(context, colors, isDark, statsAsync),
                                    ),
                                    const SizedBox(width: 24),
                                    // Right Column (Editor)
                                    Expanded(
                                      child: _buildEditorPanel(context, colors, isDark, lineCount),
                                    ),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _buildLeftPanel(context, colors, isDark, statsAsync),
                                    const SizedBox(height: 24),
                                    _buildEditorPanel(context, colors, isDark, lineCount),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLeftPanel(
    BuildContext context, 
    AppColors colors, 
    bool isDark, 
    AsyncValue<Map<String, dynamic>> statsAsync,
  ) {
    return Column(
      children: [
        // Metrics Card
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF202020) : Colors.white,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(16),
          child: statsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator.adaptive(),
              ),
            ),
            error: (error, _) => Center(
              child: Text(
                'Failed to load stats',
                style: TextStyle(color: colors.statusFailed, fontSize: 12),
              ),
            ),
            data: (stats) {
              final chunks = stats['chunks_count'] as int? ?? 0;
              final dimension = stats['embedding_dim'] as int? ?? 768;
              final status = stats['status'] as String? ?? 'ready';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.analytics_outlined, size: 16, color: colors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        'WORKSPACE METRICS',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'IBM Plex Mono',
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _formatNumber(chunks),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'Total Text Chunks',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'FAISS Vector Index',
                        style: TextStyle(fontSize: 12, color: colors.textSecondary),
                      ),
                      Text(
                        '$dimension dim',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'IBM Plex Mono',
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Sync Status',
                        style: TextStyle(fontSize: 12, color: colors.textSecondary),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1C3D2E) : const Color(0xFFEDF3EC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: status == 'ready' ? const Color(0xFF10B981) : Colors.orange,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              status == 'ready' ? 'Active' : 'Syncing',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: status == 'ready' ? colors.statusReady : colors.statusProcessing,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // Active Models Card
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF202020) : Colors.white,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(16),
          child: statsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (stats) {
              final llmModel = stats['llm_model'] as String? ?? 'qwen2.5:1.5b';
              final embeddingModel = stats['embedding_model'] as String? ?? 'gte-multilingual-base';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ACTIVE MODELS',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'IBM Plex Mono',
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Model 1
                  _buildModelRow(
                    context: context,
                    icon: Icons.psychology_outlined,
                    title: llmModel,
                    subtitle: 'LLM Generation',
                    iconBg: colors.primary.withValues(alpha: 0.1),
                    iconColor: colors.primary,
                  ),
                  const SizedBox(height: 12),
                  // Model 2
                  _buildModelRow(
                    context: context,
                    icon: Icons.scatter_plot_outlined,
                    title: embeddingModel,
                    subtitle: 'Vector Embedding',
                    iconBg: Colors.orange.withValues(alpha: 0.1),
                    iconColor: Colors.orange.shade400,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildModelRow({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconBg,
    required Color iconColor,
  }) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252525) : const Color(0xFFFBFBFA),
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorPanel(BuildContext context, AppColors colors, bool isDark, int lineCount) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF202020) : Colors.white,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Workspace Name Input
          Text(
            'WORKSPACE NAME',
            style: TextStyle(
              fontSize: 10.5,
              fontFamily: 'IBM Plex Mono',
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF252525) : const Color(0xFFFBFBFA),
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: TextField(
              controller: _nameController,
              style: TextStyle(
                fontSize: 13.5,
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Preset Chips
          Row(
            children: [
              Text(
                'PRESETS',
                style: TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'IBM Plex Mono',
                  fontWeight: FontWeight.w700,
                  color: colors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.sell_outlined, size: 12, color: colors.textSecondary),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPresetChip('Bullet Points Only', Icons.format_list_bulleted_rounded),
              _buildPresetChip('Explain Simply', Icons.lightbulb_outline_rounded),
              _buildPresetChip('Answer in Hindi', Icons.translate_rounded),
              // Plus chip
              InkWell(
                onTap: () {},
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: colors.border,
                      style: BorderStyle.solid,
                    ),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.add, size: 14, color: colors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Monospace Code Editor
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SYSTEM INSTRUCTIONS',
                style: TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'IBM Plex Mono',
                  fontWeight: FontWeight.w700,
                  color: colors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                'Markdown Supported',
                style: TextStyle(
                  fontSize: 9.5,
                  fontFamily: 'IBM Plex Mono',
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF252525) : const Color(0xFFFBFBFA),
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Line Numbers Left Column (Decorative and dynamically sized)
                  Container(
                    width: 36,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFF1F1EF),
                      border: Border(right: BorderSide(color: colors.border)),
                    ),
                    alignment: Alignment.topCenter,
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Text(
                        List.generate(lineCount, (i) => '${i + 1}').join('\n'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'IBM Plex Mono',
                          fontSize: 12,
                          height: 1.6,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                  ),

                  // Editable Text Area
                  Expanded(
                    child: TextField(
                      controller: _instructionsController,
                      maxLines: null,
                      minLines: 8,
                      keyboardType: TextInputType.multiline,
                      style: TextStyle(
                        fontFamily: 'IBM Plex Mono',
                        fontSize: 12,
                        height: 1.6,
                        color: colors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.all(12),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String presetName, IconData icon) {
    final colors = context.colors;
    final isSelected = _selectedPresets.contains(presetName);

    return InkWell(
      onTap: () => _togglePreset(presetName),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colors.primary.withValues(alpha: 0.08) : Colors.transparent,
          border: Border.all(
            color: isSelected ? colors.primary.withValues(alpha: 0.3) : colors.border,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              presetName,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? colors.primary : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(int number) {
    if (number < 1000) return number.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return number.toString().replaceAllMapped(reg, (Match m) => '${m[1]},');
  }
}
