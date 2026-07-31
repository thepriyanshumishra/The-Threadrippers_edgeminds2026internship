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
import '../../chat/widgets/mode_selector.dart';
import '../../chat/widgets/sources_used_bar.dart';
import '../../chat/widgets/model_selector.dart';
import '../../tutorial/providers/tutorial_provider.dart';
import '../../tutorial/screens/tutorial_overlay.dart';
import '../../onboarding/services/onboarding_prefs.dart';
import '../../../core/theme/theme_provider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_constants.dart';
import '../widgets/edge_telemetry_badge.dart';

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

  ChatMode _selectedMode = ChatMode.defaultMode;
  List<String> _downloadedModels = [];

  @override
  void initState() {
    super.initState();
    _loadModels();
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
    ref
        .read(chatProvider(widget.workspaceId).notifier)
        .sendMessage(text, mode: _selectedMode.apiValue);
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

  Future<void> _submitFeedback(Citation citation, bool helpful) async {
    final client = http.Client();
    try {
      final response = await client.post(
        Uri.parse('${AppConstants.backendBaseUrl}/workspaces/${widget.workspaceId}/chat/feedback'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'citation_index': citation.index,
          'citation_raw_id': citation.rawId,
          'source_id': citation.sourceId,
          'source_name': citation.sourceName,
          'snippet': citation.snippet,
          'helpful': helpful,
        }),
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(helpful
                  ? 'Thank you! Marked as helpful.'
                  : 'Feedback recorded. Marked as irrelevant.'),
              backgroundColor: context.colors.statusReady,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Failed to submit feedback: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit feedback: $e'),
            backgroundColor: context.colors.statusFailed,
          ),
        );
      }
    } finally {
      client.close();
    }
  }

  Widget _buildSourcesSidebar(
      BuildContext context, List<src_model.Source> sources, String workspaceName) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final documents = sources
        .where((s) =>
            s.type == src_model.SourceType.pdf ||
            s.type == src_model.SourceType.image ||
            s.type == src_model.SourceType.text ||
            s.type == src_model.SourceType.email ||
            s.type == src_model.SourceType.audio)
        .toList();

    final webMedia = sources
        .where(
            (s) => s.type == src_model.SourceType.youtube || s.type == src_model.SourceType.website)
        .toList();

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
                      style: TextStyle(
                          fontSize: 12, color: colors.textMuted, fontWeight: FontWeight.w500),
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
                  tooltip: 'Collapse sidebar',
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
                  context
                      .push(AppRoutes.sourceUpload.replaceAll(':workspaceId', widget.workspaceId));
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
    Color iconColor = colors.textSecondary;
    switch (source.type) {
      case src_model.SourceType.pdf:
        icon = Icons.picture_as_pdf_outlined;
        break;
      case src_model.SourceType.image:
        icon = Icons.image_outlined;
        break;
      case src_model.SourceType.audio:
        icon = Icons.audiotrack_outlined;
        iconColor = Colors.purple;
        break;
      case src_model.SourceType.youtube:
        icon = Icons.smart_display_outlined;
        iconColor = Colors.red;
        break;
      case src_model.SourceType.website:
        icon = Icons.language_outlined;
        iconColor = Colors.green;
        break;
      case src_model.SourceType.text:
        icon = Icons.description_outlined;
        iconColor = Colors.blueGrey;
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
            Icon(icon, size: 15, color: iconColor),
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

    final sourcesState = ref.read(sourcesProvider(widget.workspaceId));
    final sources = sourcesState.value ?? <src_model.Source>[];
    final matchedSource = sources.firstWhere(
      (s) => s.id == citation.sourceId || s.name == citation.sourceName,
      orElse: () => src_model.Source(
        id: '',
        name: citation.sourceName,
        type: src_model.SourceType.text,
        status: src_model.SourceStatus.ready,
        addedAt: DateTime.now(),
      ),
    );

    final docType = matchedSource.type.name.toUpperCase();

    final pagesText = (citation.pages != null && citation.pages!.isNotEmpty)
        ? 'Page ${citation.pages!.join(", ")}'
        : 'N/A';

    final confidenceText = (citation.score != null && citation.score! > 0)
        ? '${(citation.score! * 100).toStringAsFixed(1)}%'
        : 'N/A';

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
                tooltip: 'Close inspector',
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
                            docType,
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
                                pagesText,
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
                                confidenceText,
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

              // PDF page preview rendering dynamically
              if (matchedSource.type == src_model.SourceType.pdf && citation.sourceId != null) ...[
                Text(
                  'PAGE PREVIEW',
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'IBM Plex Mono',
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.network(
                    '${AppConstants.backendBaseUrl}/workspaces/${widget.workspaceId}/sources/${citation.sourceId}/pages/${(citation.pages != null && citation.pages!.isNotEmpty) ? citation.pages!.first : 1}',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Text(
                          'Preview not available',
                          style: TextStyle(color: colors.textMuted, fontSize: 11),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Segment text box — only shown when snippet is available
              if (citation.snippet != null && citation.snippet!.isNotEmpty) ...[
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
                    citation.snippet!,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
              ] else ...[
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: colors.border, width: 3),
                    ),
                  ),
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    'No excerpt available for this source.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textMuted,
                      fontStyle: FontStyle.italic,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
              ],

              // CTA Action
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final urlStr = citation.timestampUrl ?? matchedSource.url;
                    if (urlStr != null && urlStr.isNotEmpty) {
                      launchUrl(Uri.parse(urlStr), mode: LaunchMode.externalApplication);
                    } else if (matchedSource.id.isNotEmpty && matchedSource.path != null) {
                      final downloadUrl =
                          '${AppConstants.backendBaseUrl}/workspaces/${widget.workspaceId}/sources/${matchedSource.id}/download';
                      launchUrl(Uri.parse(downloadUrl));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Original document not accessible'),
                          backgroundColor: colors.statusFailed,
                        ),
                      );
                    }
                  },
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
                  onPressed: () => _submitFeedback(citation, true),
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
                  onPressed: () => _submitFeedback(citation, false),
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

  Widget _buildEmptyChatState(BuildContext context, List<src_model.Source> sources) {
    final colors = context.colors;
    final hasSources = sources.isNotEmpty;
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
              hasSources ? Icons.auto_awesome : Icons.folder_open_rounded,
              size: 24,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasSources ? 'Workspace Ready' : 'No Sources Yet',
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
              hasSources
                  ? "Ask me anything about your workspace sources."
                  : "Add a source to start chatting with your documents.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
          if (!hasSources) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                context.push(AppRoutes.sourceUpload.replaceAll(':workspaceId', widget.workspaceId));
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Source'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _modeEmoji(String? mode) {
    switch (mode) {
      case 'strict': return '🔒';
      case 'explore': return '✨';
      default: return '⚡';
    }
  }

  String _modeLabel(String? mode) {
    switch (mode) {
      case 'strict': return 'Strict';
      case 'explore': return 'Explore';
      default: return 'Default';
    }
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
                    gradient: isUser
                        ? const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isUser ? null : bubbleBg,
                    border: isUser ? null : Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: isUser
                      ? SelectableText(
                          message.text,
                          style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.5),
                        )
                      : MarkdownBody(
                          data: message.text,
                          selectable: true,
                          builders: {
                            'code': CodeElementBuilder(context),
                          },
                          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                            p: TextStyle(color: colors.textPrimary, fontSize: 13.5, height: 1.55),
                            h1: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold, height: 1.4),
                            h2: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold, height: 1.35),
                            h3: TextStyle(color: colors.primary, fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.3),
                            h4: TextStyle(color: colors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600),
                            listBullet: TextStyle(color: colors.primary, fontSize: 13.5, fontWeight: FontWeight.bold),
                            blockSpacing: 10,
                            listIndent: 20,
                            blockquoteDecoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(4),
                              border: Border(left: BorderSide(color: colors.primary, width: 3)),
                            ),
                            blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            blockquote: TextStyle(color: colors.textSecondary, fontSize: 13, fontStyle: FontStyle.italic),
                            code: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: colors.textPrimary,
                              backgroundColor: colors.surfaceElevated,
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: colors.surfaceElevated,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: colors.border),
                            ),
                            codeblockPadding: const EdgeInsets.all(12),
                          ),
                        ),
                ),
                if (!isUser && message.mode.isNotEmpty) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 4, left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.sidebarBackground,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.border.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_modeEmoji(message.mode), style: const TextStyle(fontSize: 10)),
                        const SizedBox(width: 4),
                        Text(_modeLabel(message.mode), style: TextStyle(fontSize: 10, color: colors.textMuted)),
                      ],
                    ),
                  ),
                ],
                if (!isUser) ...[
                  // NotebookLM-style Sources Used bar
                  if (message.citations.isNotEmpty)
                    SourcesUsedBar(citations: message.citations),
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
                child:
                    const Icon(Icons.check_circle_outline_rounded, size: 36, color: Colors.green),
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
                    tooltip: 'Expand sidebar',
                    onPressed: () {
                      setState(() {
                        _isSourcesPanelCollapsed = false;
                      });
                    },
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add, size: 16),
                    tooltip: 'Add source',
                    onPressed: () {
                      context.push(
                          AppRoutes.sourceUpload.replaceAll(':workspaceId', widget.workspaceId));
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
                          onPressed: () => _triggerQuickAction(
                              'Create comprehensive study notes from this workspace.'),
                          icon: const Icon(Icons.note_alt_outlined, size: 13),
                          label: const Text('Create Study Notes'),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colors.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _triggerQuickAction(
                              'Generate a quiz to test my understanding of the sources.'),
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
                      const EdgeTelemetryBadge(),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.file_download_outlined, size: 18),
                        tooltip: 'Export Workspace & Transcript',
                        onPressed: () async {
                          final exportUrl = '${AppConstants.backendBaseUrl}/workspaces/${widget.workspaceId}/export';
                          final uri = Uri.parse(exportUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                      // Settings and Delete icons
                      IconButton(
                        key: TutorialKeys.settingsBtn,
                        icon: const Icon(Icons.settings_outlined, size: 18),
                        tooltip: 'Workspace settings',
                        onPressed: () {
                          context.push(AppRoutes.workspaceSettings
                              .replaceAll(':workspaceId', widget.workspaceId));
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        tooltip: 'Clear chat',
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
                                Icon(Icons.chat_bubble_outline_rounded,
                                    size: 36, color: colors.textMuted),
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
                          ? _buildEmptyChatState(context, sources)
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
                        Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF202020)
                                : const Color(0xFFFBFBFA),
                            border: Border.all(color: colors.border, width: 1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              ModeSelectorWidget(
                                selectedMode: _selectedMode,
                                onModeChanged: (mode) => setState(() => _selectedMode = mode),
                              ),
                              const SizedBox(width: 4),
                              Container(height: 20, width: 1, color: colors.divider),
                              const SizedBox(width: 4),
                              Expanded(
                                child: TextField(
                                  key: TutorialKeys.chatInput,
                                  controller: _messageController,
                                  focusNode: _focusNode,
                                  minLines: 1,
                                  maxLines: 5,
                                  style: TextStyle(color: colors.textPrimary, fontSize: 13.5),
                                  decoration: InputDecoration(
                                    hintText: 'Ask your workspace a question...',
                                    hintStyle: TextStyle(color: colors.textMuted, fontSize: 13.5),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    filled: false,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                  onSubmitted: (_) => hasReadySources ? _sendMessage() : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ModelSelectorWidget(
                                availableModels: _downloadedModels,
                                selectedModel: _downloadedModels
                                        .contains(ref.watch(activeModelProvider))
                                    ? ref.watch(activeModelProvider)
                                    : (_downloadedModels.isNotEmpty ? _downloadedModels.first : ''),
                                onModelChanged: (newValue) {
                                  ref.read(activeModelProvider.notifier).state = newValue;
                                  OnboardingPrefs.write({'activeModel': newValue});
                                },
                                onAddModel: () {
                                  context.push('/model-downloader').then((_) => _loadModels());
                                },
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: chatState.isStreaming ? 'Stop generation' : 'Send message',
                                onPressed: chatState.isStreaming
                                    ? () {
                                        ref
                                            .read(chatProvider(widget.workspaceId).notifier)
                                            .stopAddressing();
                                      }
                                    : (hasReadySources ? _sendMessage : null),
                                icon: chatState.isStreaming
                                    ? const Icon(Icons.stop_rounded, size: 16, color: Colors.white)
                                    : Icon(Icons.arrow_upward_rounded,
                                        size: 16,
                                        color: hasReadySources ? colors.primary : colors.textMuted),
                                style: IconButton.styleFrom(
                                  backgroundColor: chatState.isStreaming
                                      ? colors.statusFailed
                                      : (hasReadySources
                                          ? colors.primary.withValues(alpha: 0.1)
                                          : Colors.transparent),
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
          description:
              'Ask questions, search details, or summarize documents. Every response includes direct citations back to the source files.',
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
          description:
              'Tweak retrieval options, configure your local LLM model temperature, or change themes and typography here.',
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
