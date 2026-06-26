import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:markdown/markdown.dart' as md;
import '../../../core/theme/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../providers/workspace_providers.dart';
import '../../source_upload/models/source.dart' as src_model;
import '../../source_upload/providers/source_providers.dart';
import '../../chat/models/chat_message.dart';
import '../../chat/models/citation.dart';
import '../../chat/providers/chat_providers.dart';
import '../../tutorial/providers/tutorial_provider.dart';
import '../../tutorial/screens/tutorial_overlay.dart';
import '../../onboarding/services/onboarding_prefs.dart';
import '../../onboarding/models/onboarding_state.dart';
import '../../../core/theme/theme_provider.dart';

class WorkspaceScreen extends ConsumerStatefulWidget {
  final String workspaceId;

  const WorkspaceScreen({super.key, required this.workspaceId});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isSourcesPanelCollapsed = false;
  Citation? _selectedCitation;
  bool _isInputFocused = false;
  bool _isStrictSourceMode = true;
  List<String> _downloadedModels = [];

  @override
  void initState() {
    super.initState();
    _loadModels();
    _focusNode.addListener(() {
      setState(() {
        _isInputFocused = _focusNode.hasFocus;
      });
    });
    _focusNode.onKeyEvent = (node, event) {
      final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter;
      final isShift = HardwareKeyboard.instance.isShiftPressed ||
          HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
          HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);

      if (isEnter && !isShift) {
        if (event is KeyDownEvent) {
          _sendMessage();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  Future<void> _loadModels() async {
    final list = await OnboardingPrefs.getDownloadedModels();
    if (mounted) {
      setState(() {
        _downloadedModels = list;
      });
    }
  }

  String _cleanModelName(String modelId) {
    try {
      final match = curatedModelRegistry.firstWhere((m) => m.id == modelId);
      return match.name.split(' (').first;
    } catch (_) {
      return modelId;
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    ref.read(chatProvider(widget.workspaceId).notifier).sendMessage(text, isStrict: _isStrictSourceMode);
    _focusNode.requestFocus();
    _scrollToBottom();
  }

  void _showClearChatConfirmation(BuildContext context) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Conversation?'),
        content: const Text('This will delete all messages in the current chat history locally.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(chatProvider(widget.workspaceId).notifier).clearChat();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.statusFailed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _triggerQuickAction(String query) {
    _messageController.text = query;
    _sendMessage();
  }

  String _getMockRetrievedSegment(Citation citation) {
    if (citation.index == 1) {
      return "...previous iterations of the cooling array demonstrated failure modes under sustained operation. However, the revised prototype testing concluded last month. The integration of the phase-change material reduces peak heat loads by approximately 22% during high-stress operational cycles, validating the simulation models presented in section 4.1. Further analysis of the structural integrity post-thermal cycling indicates negligible degradation of the primary casing...";
    } else if (citation.index == 2) {
      return "...market research shows high consumer demand for integrated document indexing solutions. Customer feedback indicates 68% of enterprise clients requested GraphQL APIs, which drove the recent product roadmap decisions. Marketing messaging outlines GraphQL support from day 1 for enterprise clients, which conflicts with engineering constraints...";
    } else {
      return "...as documented in ${citation.sourceName}, the current pipeline generates text chunks using an overlapping sliding window strategy, then produces dense vector representations. These embeddings are mapped to localized index coordinates, enabling fast top-k document retrieval during RAG synthesis...";
    }
  }

  Widget _buildSourcesSidebar(BuildContext context, List<src_model.Source> sources, String workspaceName) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final documents = sources.where((s) => 
      s.type == src_model.SourceType.pdf || 
      s.type == src_model.SourceType.image || 
      s.type == src_model.SourceType.text ||
      s.type == src_model.SourceType.email ||
      s.type == src_model.SourceType.audio
    ).toList();

    final webMedia = sources.where((s) => 
      s.type == src_model.SourceType.youtube || 
      s.type == src_model.SourceType.website
    ).toList();

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF202020) : const Color(0xFFFBFBFA),
        border: Border(
          right: BorderSide(color: colors.divider, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back to All Workspaces
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.go('/'),
              hoverColor: colors.textPrimary.withValues(alpha: 0.04),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.arrow_back_rounded, size: 13, color: colors.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      'All Workspaces',
                      style: TextStyle(fontSize: 12, color: colors.textMuted, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Sidebar Header — shows workspace name
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        workspaceName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${sources.length} Sources',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_double_arrow_left_rounded, size: 16),
                  onPressed: () {
                    setState(() {
                      _isSourcesPanelCollapsed = true;
                    });
                  },
                ),
              ],
            ),
          ),

          // Add Source CTA button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  context.push(AppRoutes.sourceUpload.replaceAll(':workspaceId', widget.workspaceId));
                },
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Source'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Categorized Sources List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                if (documents.isNotEmpty) ...[
                  Text(
                    'DOCUMENTS (${documents.length})',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'IBM Plex Mono',
                      fontWeight: FontWeight.w600,
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...documents.map((s) => _buildSourceListTile(context, s)),
                  const SizedBox(height: 20),
                ],
                if (webMedia.isNotEmpty) ...[
                  Text(
                    'WEB & MEDIA (${webMedia.length})',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'IBM Plex Mono',
                      fontWeight: FontWeight.w600,
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...webMedia.map((s) => _buildSourceListTile(context, s)),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),

          // Paste Text Box at bottom
          Padding(
            padding: const EdgeInsets.all(12),
            child: InkWell(
              onTap: () {
                context.push(AppRoutes.sourceUpload.replaceAll(':workspaceId', widget.workspaceId));
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.border, style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  children: [
                    Icon(Icons.description_outlined, size: 18, color: colors.textMuted),
                    const SizedBox(height: 6),
                    Text(
                      'Paste URL or Text',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ctrl+V anywhere to add',
                      style: TextStyle(fontSize: 9.5, color: colors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceListTile(BuildContext context, src_model.Source source) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    IconData icon;
    switch (source.type) {
      case src_model.SourceType.pdf:
        icon = Icons.picture_as_pdf_outlined;
        break;
      case src_model.SourceType.image:
        icon = Icons.image_outlined;
        break;
      case src_model.SourceType.audio:
        icon = Icons.mic_none_outlined;
        break;
      case src_model.SourceType.youtube:
        icon = Icons.play_circle_outline_rounded;
        break;
      case src_model.SourceType.website:
        icon = Icons.link_rounded;
        break;
      case src_model.SourceType.text:
        icon = Icons.notes_outlined;
        break;
      case src_model.SourceType.email:
        icon = Icons.email_outlined;
        break;
    }

    Color badgeColor;
    Color badgeBg;
    String badgeText;

    switch (source.status) {
      case src_model.SourceStatus.ready:
        badgeColor = colors.statusReady;
        badgeBg = colors.statusReadyBg;
        badgeText = 'DONE';
        break;
      case src_model.SourceStatus.processing:
        badgeColor = colors.statusProcessing;
        badgeBg = colors.statusProcessingBg;
        badgeText = 'PROCESSING';
        break;
      case src_model.SourceStatus.failed:
        badgeColor = colors.statusFailed;
        badgeBg = colors.statusFailedBg;
        badgeText = 'FAILED';
        break;
      case src_model.SourceStatus.pending:
        badgeColor = colors.textSecondary;
        badgeBg = colors.border;
        badgeText = 'PENDING';
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF252525) : Colors.white,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 15, color: colors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'IBM Plex Mono',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceInspector(BuildContext context, Citation citation) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Drawer Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.find_in_page_outlined, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Source Inspector',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    _selectedCitation = null;
                  });
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Metadata Card
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF252525) : const Color(0xFFFBFBFA),
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'DOCUMENT',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'IBM Plex Mono',
                            color: colors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'PDF',
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      citation.sourceName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PAGE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'IBM Plex Mono',
                                  color: colors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '42 of 156',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CONFIDENCE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'IBM Plex Mono',
                                  color: colors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '98.4%',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Segment text box
              Row(
                children: [
                  Icon(Icons.format_quote_rounded, size: 14, color: colors.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    'RETRIEVED SEGMENT',
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'IBM Plex Mono',
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Colors.orange.shade300, width: 3),
                  ),
                ),
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  citation.snippet ?? _getMockRetrievedSegment(citation),
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textPrimary,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // CTA Action
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text('Jump to Original Document'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Feedback options
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.thumb_up_alt_outlined, size: 13),
                  label: const Text('Helpful'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.thumb_down_alt_outlined, size: 13),
                  label: const Text('Irrelevant'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeToggleOption({
    required String label,
    required String tooltip,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isActive
            ? colors.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          hoverColor: colors.textPrimary.withValues(alpha: 0.05),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(
                color: isActive ? colors.primary.withValues(alpha: 0.4) : colors.border,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? colors.primary : colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyChatState(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.sidebarBackground,
              shape: BoxShape.circle,
              border: Border.all(color: colors.border),
            ),
            child: Icon(
              Icons.auto_awesome,
              size: 24,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Workspace Ready',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              "I've indexed your workspace sources. Ask me anything about them, or use a quick action above.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessage message) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = message.isUser;
    final bubbleBg = isUser ? colors.sidebarBackground : colors.surface;


    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.adb, color: colors.primary, size: 16),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.60,
                  ),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: bubbleBg,
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: isUser
                      ? SelectableText(
                          message.text,
                          style: TextStyle(color: colors.textPrimary, fontSize: 13.5, height: 1.5),
                        )
                      : MarkdownBody(
                          data: message.text,
                          selectable: true,
                          builders: {
                            'code': CodeElementBuilder(context),
                          },
                          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                            p: TextStyle(color: colors.textPrimary, fontSize: 13.5, height: 1.5),
                            listBullet: TextStyle(color: colors.primary, fontSize: 13.5),
                            code: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: colors.textPrimary,
                              backgroundColor: colors.surfaceElevated,
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: colors.surfaceElevated,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: colors.border),
                            ),
                          ),
                        ),
                ),
                if (!isUser) ...[
                  const SizedBox(height: 8),
                  // SOURCES USED Header and capsules
                  if (message.citations.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 6),
                      child: Text(
                        'SOURCES USED',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontFamily: 'IBM Plex Mono',
                          fontWeight: FontWeight.w700,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 28,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: message.citations.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 6),
                        itemBuilder: (context, index) {
                          final cit = message.citations[index];
                          return Tooltip(
                            richMessage: WidgetSpan(
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 350),
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.description_outlined, color: colors.primary, size: 14),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            cit.sourceName,
                                            style: TextStyle(
                                              color: colors.textPrimary,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (cit.snippet != null && cit.snippet!.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        cit.snippet!,
                                        style: TextStyle(
                                          color: colors.textSecondary,
                                          fontSize: 11,
                                          height: 1.4,
                                        ),
                                        maxLines: 6,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? const Color(0xFF1E1E1E).withValues(alpha: 0.95)
                                  : Colors.white.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colors.border),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            preferBelow: false,
                            verticalOffset: 20,
                            waitDuration: const Duration(milliseconds: 200),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedCitation = cit;
                                });
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF252525) : const Color(0xFFFBFBFA),
                                  border: Border.all(color: colors.border),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.description_outlined, size: 12, color: colors.textSecondary),
                                    const SizedBox(width: 4),
                                    Text(
                                      '[${cit.index}]',
                                      style: TextStyle(
                                        color: colors.primary,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      cit.sourceName,
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],

              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 12),
            CircleAvatar(
              radius: 14,
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
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.adb, color: colors.primary, size: 16),
          ),
          const SizedBox(width: 12),
          Text(
            'Synthesizing answer...',
            style: TextStyle(
              fontSize: 12.5,
              color: colors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
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
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeWorkspaceState = ref.watch(activeWorkspaceProvider(widget.workspaceId));
    final sourcesState = ref.watch(sourcesProvider(widget.workspaceId));
    final chatState = ref.watch(chatProvider(widget.workspaceId));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tutorialState = ref.watch(tutorialProvider);

    final String workspaceName = activeWorkspaceState.maybeWhen(
      data: (w) => w.name,
      orElse: () => 'Workspace Chat',
    );

    final List<src_model.Source> sources = sourcesState.maybeWhen(
      data: (list) => list,
      orElse: () => <src_model.Source>[],
    );

    final hasReadySources = sources.any((s) => s.status == src_model.SourceStatus.ready);

    Widget body = Scaffold(
      body: Row(
        children: [
          // Sidebar sources panel
          if (!_isSourcesPanelCollapsed)
            _buildSourcesSidebar(context, sources, workspaceName)
          else
            Container(
              width: 48,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF202020) : const Color(0xFFFBFBFA),
                border: Border(right: BorderSide(color: colors.divider)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  IconButton(
                    icon: const Icon(Icons.keyboard_double_arrow_right_rounded, size: 16),
                    onPressed: () {
                      setState(() {
                        _isSourcesPanelCollapsed = false;
                      });
                    },
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add, size: 16),
                    onPressed: () {
                      context.push(AppRoutes.sourceUpload.replaceAll(':workspaceId', widget.workspaceId));
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

          // Main Chat viewport
          Expanded(
            child: Column(
              children: [
                // Top Header Row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: colors.divider)),
                  ),
                  child: Row(
                    children: [
                      // Quick prompt template chips
                      if (hasReadySources) ...[
                        OutlinedButton.icon(
                          onPressed: () => _triggerQuickAction('Summarize the workspace sources.'),
                          icon: const Icon(Icons.summarize_outlined, size: 13),
                          label: const Text('Summarize Workspace'),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colors.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _triggerQuickAction('Create comprehensive study notes from this workspace.'),
                          icon: const Icon(Icons.note_alt_outlined, size: 13),
                          label: const Text('Create Study Notes'),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colors.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _triggerQuickAction('Generate a quiz to test my understanding of the sources.'),
                          icon: const Icon(Icons.quiz_outlined, size: 13),
                          label: const Text('Generate Quiz'),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colors.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                      ] else ...[
                        Text(
                          workspaceName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                      const Spacer(),
                      // Settings and Download icons
                      IconButton(
                        key: TutorialKeys.settingsBtn,
                        icon: const Icon(Icons.settings_outlined, size: 18),
                        onPressed: () {
                          context.push(AppRoutes.workspaceSettings.replaceAll(':workspaceId', widget.workspaceId));
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        onPressed: () => _showClearChatConfirmation(context),
                      ),
                    ],
                  ),
                ),

                // Chat Messages List
                Expanded(
                  child: !hasReadySources
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.chat_bubble_outline_rounded, size: 36, color: colors.textMuted),
                                const SizedBox(height: 16),
                                Text(
                                  sources.isEmpty
                                      ? 'Add sources to get started.'
                                      : 'Prepare index generation on Upload screen first.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: colors.textMuted, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        )
                      : chatState.messages.isEmpty
                          ? _buildEmptyChatState(context)
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              itemCount: chatState.messages.length + (chatState.isLoading ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == chatState.messages.length) {
                                  return _buildTypingIndicator(context);
                                }
                                return _buildMessageBubble(context, chatState.messages[index]);
                              },
                            ),
                ),

                // Chat Input box
                Container(
                  padding: const EdgeInsets.all(16),
                  child: SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildModeToggleOption(
                              label: 'Strict Source Mode 🔒',
                              tooltip: 'Answers strictly from documents. Refuses if not found.',
                              isActive: _isStrictSourceMode,
                              onTap: () => setState(() => _isStrictSourceMode = true),
                            ),
                            const SizedBox(width: 8),
                            _buildModeToggleOption(
                              label: 'Creative AI Mode 🌐',
                              tooltip: 'Sources are prioritized, but general AI knowledge is used to elaborate.',
                              isActive: !_isStrictSourceMode,
                              onTap: () => setState(() => _isStrictSourceMode = false),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF202020) : const Color(0xFFFBFBFA),
                            border: Border.all(
                              color: _isInputFocused ? colors.primary : colors.border,
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.attach_file_rounded, size: 18, color: colors.textSecondary),
                                onPressed: () {
                                  context.push(AppRoutes.sourceUpload.replaceAll(':workspaceId', widget.workspaceId));
                                },
                              ),
                              Expanded(
                                child: TextField(
                                  key: TutorialKeys.chatInput,
                                  controller: _messageController,
                                  focusNode: _focusNode,
                                  enabled: hasReadySources,
                                  minLines: 1,
                                  maxLines: 5,
                                  style: TextStyle(color: colors.textPrimary, fontSize: 13.5),
                                  decoration: InputDecoration(
                                    hintText: 'Ask about your documents...',
                                    hintStyle: TextStyle(color: colors.textMuted, fontSize: 13.5),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    filled: false,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Theme(
                                data: Theme.of(context).copyWith(
                                  canvasColor: colors.sidebarBackground,
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _downloadedModels.contains(ref.watch(activeModelProvider))
                                        ? ref.watch(activeModelProvider)
                                        : (_downloadedModels.isNotEmpty ? _downloadedModels.first : null),
                                    icon: Icon(Icons.arrow_drop_down_rounded, color: colors.textSecondary),
                                    style: TextStyle(color: colors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
                                    onChanged: (newValue) {
                                      if (newValue == 'add_model') {
                                        context.push('/model-downloader').then((_) => _loadModels());
                                      } else if (newValue != null) {
                                        ref.read(activeModelProvider.notifier).state = newValue;
                                        OnboardingPrefs.write({'activeModel': newValue});
                                      }
                                    },
                                    items: [
                                      ..._downloadedModels.map((modelId) {
                                        return DropdownMenuItem<String>(
                                          value: modelId,
                                          child: Text(_cleanModelName(modelId)),
                                        );
                                      }),
                                      const DropdownMenuItem<String>(
                                        value: 'add_model',
                                        child: Row(
                                          children: [
                                            Icon(Icons.add, size: 14, color: Colors.blue),
                                            SizedBox(width: 4),
                                            Text('Add Model', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: chatState.isStreaming
                                    ? const Icon(Icons.stop_rounded, size: 16, color: Colors.white)
                                    : Icon(Icons.arrow_upward_rounded, size: 16, color: hasReadySources ? colors.primary : colors.textMuted),
                                onPressed: chatState.isStreaming
                                    ? () {
                                        ref.read(chatProvider(widget.workspaceId).notifier).stopAddressing();
                                      }
                                    : (hasReadySources ? _sendMessage : null),
                                style: IconButton.styleFrom(
                                  backgroundColor: chatState.isStreaming
                                      ? colors.statusFailed
                                      : (hasReadySources ? colors.primary.withValues(alpha: 0.1) : Colors.transparent),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'AI can make mistakes. Verify important information with the source docs.',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontFamily: 'IBM Plex Mono',
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Source Inspector Panel (Sliding Drawer on citation select)
          if (_selectedCitation != null)
            Container(
              width: MediaQuery.of(context).size.width * 0.32,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF202020) : Colors.white,
                border: Border(left: BorderSide(color: colors.divider)),
              ),
              child: _buildSourceInspector(context, _selectedCitation!),
            ),
        ],
      ),
    );

    if (tutorialState.isActive) {
      if (tutorialState.currentStep == TutorialStep.chat) {
        body = TutorialOverlay(
          targetKey: TutorialKeys.chatInput,
          title: 'Chat with your Workspace',
          description: 'Ask questions, search details, or summarize documents. Every response includes direct citations back to the source files.',
          onNext: () {
            ref.read(tutorialProvider.notifier).nextStep();
          },
          onSkip: () => ref.read(tutorialProvider.notifier).skipTutorial(),
          child: body,
        );
      } else if (tutorialState.currentStep == TutorialStep.settings) {
        body = TutorialOverlay(
          targetKey: TutorialKeys.settingsBtn,
          title: 'Workspace Settings',
          description: 'Tweak retrieval options, configure your local LLM model temperature, or change themes and typography here.',
          onNext: () {
            ref.read(tutorialProvider.notifier).nextStep();
          },
          onSkip: () => ref.read(tutorialProvider.notifier).skipTutorial(),
          child: body,
        );
      } else if (tutorialState.currentStep == TutorialStep.done) {
        body = Stack(
          children: [
            body,
            _buildDoneOverlay(context, ref),
          ],
        );
      }
    }

    return body;
  }
}

class CodeElementBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  CodeElementBuilder(this.context);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    if (!text.contains('\n')) {
      return null;
    }

    String language = '';
    if (element.attributes.containsKey('class')) {
      final className = element.attributes['class'] ?? '';
      if (className.startsWith('language-')) {
        language = className.substring('language-'.length);
      }
    }
    
    final codeText = text.trimRight();

    return CodeBlockWidget(
      codeText: codeText,
      language: language,
    );
  }
}

class CodeBlockWidget extends StatefulWidget {
  final String codeText;
  final String language;

  const CodeBlockWidget({
    super.key,
    required this.codeText,
    required this.language,
  });

  @override
  State<CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<CodeBlockWidget> {
  bool _copied = false;

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.codeText));
    setState(() {
      _copied = true;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _copied = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final displayLanguage = widget.language.toUpperCase();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.sidebarBackground,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
              border: Border(
                bottom: BorderSide(color: colors.border),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  displayLanguage.isEmpty ? 'CODE' : displayLanguage,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: InkWell(
                    onTap: _copyToClipboard,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _copied ? Icons.check_rounded : Icons.copy_rounded,
                            size: 13,
                            color: _copied ? colors.statusReady : colors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _copied ? 'Copied' : 'Copy',
                            style: TextStyle(
                              color: _copied ? colors.statusReady : colors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                widget.codeText,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
