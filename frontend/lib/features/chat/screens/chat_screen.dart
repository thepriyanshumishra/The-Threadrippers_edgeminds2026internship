// features/chat/screens/chat_screen.dart
// Purpose: Chat screen — primary interaction screen for workspace knowledge.
// Responsibilities: Display chat messages area, input box, citations, loading state.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_provider.dart';
import '../../onboarding/services/onboarding_prefs.dart';
import '../../onboarding/models/onboarding_state.dart';
import '../models/chat_message.dart';
import '../models/citation.dart';
import '../providers/chat_providers.dart';
import '../../tutorial/providers/tutorial_provider.dart';
import '../../tutorial/screens/tutorial_overlay.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String workspaceId;

  const ChatScreen({super.key, required this.workspaceId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isStrictSourceMode = true;
  List<String> _downloadedModels = [];

  @override
  void initState() {
    super.initState();
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
    _loadModels();
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final chatState = ref.watch(chatProvider(widget.workspaceId));
    final tutorialState = ref.watch(tutorialProvider);

    // Listen for error messages and show a SnackBar
    ref.listen<ChatState>(chatProvider(widget.workspaceId), (previous, next) {
      if (next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: colors.statusFailed,
            behavior: SnackBarBehavior.floating,
          ),
        );
        ref.read(chatProvider(widget.workspaceId).notifier).clearError();
      }
      if (next.messages.length > (previous?.messages.length ?? 0)) {
        _scrollToBottom();
      }
    });

    Widget body = Scaffold(
      appBar: AppBar(
        title: const Text('Workspace Chat'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // --- Messages Area ---
          Expanded(
            child: chatState.messages.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    itemCount: chatState.messages.length + (chatState.isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == chatState.messages.length) {
                        return _buildSkeletonBubble(context);
                      }
                      final isLast = index == chatState.messages.length - 1;
                      return _buildMessageBubble(context, chatState.messages[index], isLast: isLast);
                    },
                  ),
          ),

          // --- Chat Input ---
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.background,
              border: Border(
                top: BorderSide(color: colors.divider, width: 1),
              ),
            ),
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          key: TutorialKeys.chatInput,
                          controller: _messageController,
                          focusNode: _focusNode,
                          minLines: 1,
                          maxLines: 5,
                          style: TextStyle(color: colors.textPrimary),
                          decoration: const InputDecoration(
                            hintText: 'Ask your workspace a question...',
                          ),
                          onSubmitted: (_) => _sendMessage(),
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
                            style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
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
                        onPressed: chatState.isStreaming
                            ? () {
                                ref.read(chatProvider(widget.workspaceId).notifier).stopAddressing();
                              }
                            : _sendMessage,
                        icon: chatState.isStreaming
                            ? const Icon(Icons.stop_rounded, size: 16, color: Colors.white)
                            : const Icon(Icons.send_rounded),
                        color: colors.primary,
                        style: IconButton.styleFrom(
                          backgroundColor: chatState.isStreaming ? colors.statusFailed : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (tutorialState.isActive && tutorialState.currentStep == TutorialStep.chat) {
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
    }

    return body;
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

  Widget _buildEmptyState(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.forum_outlined, size: 64, color: colors.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 24),
            Text(
              'What would you like to explore?',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                _QuickActionChip(
                  label: '✦  Summarize Workspace',
                  onTap: () {
                    _messageController.text = 'Summarize the references across this workspace.';
                    _sendMessage();
                  },
                ),
                _QuickActionChip(
                  label: '✦  Key Concepts',
                  onTap: () {
                    _messageController.text = 'List the key concepts covered in the documents.';
                    _sendMessage();
                  },
                ),
                _QuickActionChip(
                  label: '✦  Create Timeline',
                  onTap: () {
                    _messageController.text = 'Provide a timeline of major events mentioned.';
                    _sendMessage();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessage message, {required bool isLast}) {
    final colors = context.colors;
    final alignment = message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleBg = message.isUser ? colors.sidebarBackground : colors.primarySubtle;
    final textStyle = TextStyle(
      color: colors.textPrimary,
      fontSize: 14,
      height: 1.5,
    );

    // If it is streaming and has no text yet, we show a shimmer block instead of empty bubble
    if (!message.isUser && message.text.isEmpty) {
      return _buildSkeletonBubble(context);
    }

    final isStreaming = isLast && !message.isUser && message.citations.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bubbleBg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(message.isUser ? 12 : 0),
                bottomRight: Radius.circular(message.isUser ? 0 : 12),
              ),
              border: Border.all(color: colors.border),
            ),
            child: isStreaming
                ? SelectableText.rich(
                    TextSpan(
                      text: message.text,
                      style: textStyle,
                      children: const [
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: EdgeInsets.only(left: 2),
                            child: _FlashingCursor(),
                          ),
                        ),
                      ],
                    ),
                  )
                : MarkdownBody(
                    data: message.text,
                    styleSheet: MarkdownStyleSheet(
                      p: textStyle,
                      strong: textStyle.copyWith(fontWeight: FontWeight.bold),
                      em: textStyle.copyWith(fontStyle: FontStyle.italic),
                      listBullet: textStyle,
                      h1: textStyle.copyWith(fontSize: 18, fontWeight: FontWeight.bold),
                      h2: textStyle.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
                      h3: textStyle.copyWith(fontSize: 15, fontWeight: FontWeight.bold),
                      code: TextStyle(
                        fontFamily: 'IBM Plex Mono',
                        fontSize: 12,
                        color: colors.primary,
                        backgroundColor: colors.sidebarBackground,
                      ),
                      codeblockPadding: const EdgeInsets.all(12),
                      codeblockDecoration: BoxDecoration(
                        color: colors.sidebarBackground,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.border),
                      ),
                    ),
                    inlineSyntaxes: [
                      CitationSyntax(),
                    ],
                    builders: {
                      'citation': CitationElementBuilder(
                        message.citations,
                        onTap: (cit) => _showCitationDetails(context, cit),
                      ),
                    },
                  ),
          ),
          if (!message.isUser && message.citations.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: message.citations.map((cit) => _buildCitationChip(context, cit)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCitationChip(BuildContext context, Citation citation) {
    final colors = context.colors;
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
                      citation.sourceName,
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
              if (citation.snippet != null && citation.snippet!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  citation.snippet!,
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
        onTap: () => _showCitationDetails(context, citation),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.sidebarBackground,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '[${citation.index}]',
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                citation.sourceName,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonBubble(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.7,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.primarySubtle,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
            border: Border.all(color: colors.border),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _ShimmerPlaceholder(width: double.infinity, height: 14),
              SizedBox(height: 8),
              _ShimmerPlaceholder(width: double.infinity, height: 14),
              SizedBox(height: 8),
              _ShimmerPlaceholder(width: 120, height: 14),
            ],
          ),
        ),
      ),
    );
  }

  void _showCitationDetails(BuildContext context, Citation citation) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.article_outlined, color: colors.primary),
              const SizedBox(width: 8),
              Text('Footnote [${citation.index}]'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Source Document Name:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(citation.sourceName),
              const SizedBox(height: 12),
              if (citation.snippet != null && citation.snippet!.isNotEmpty) ...[
                const Text('Snippet:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(citation.snippet!),
                const SizedBox(height: 12),
              ],
              const Text('Raw Chunk Citation ID:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(citation.rawId, style: const TextStyle(fontFamily: 'monospace')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickActionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: colors.sidebarBackground,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _FlashingCursor extends StatefulWidget {
  const _FlashingCursor();

  @override
  State<_FlashingCursor> createState() => _FlashingCursorState();
}

class _FlashingCursorState extends State<_FlashingCursor> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 2,
        height: 15,
        color: colors.primary,
      ),
    );
  }
}

class _ShimmerPlaceholder extends StatefulWidget {
  final double width;
  final double height;

  const _ShimmerPlaceholder({
    required this.width,
    required this.height,
  });

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: colors.textSecondary.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

class CitationSyntax extends md.InlineSyntax {
  CitationSyntax() : super(r'\[(\d+)\]');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final indexStr = match.group(1);
    final element = md.Element.withTag('citation')
      ..attributes['index'] = indexStr ?? '';
    parser.addNode(element);
    return true;
  }
}

class CitationElementBuilder extends MarkdownElementBuilder {
  final List<Citation> citations;
  final Function(Citation) onTap;

  CitationElementBuilder(this.citations, {required this.onTap});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final indexStr = element.attributes['index'];
    if (indexStr == null) return null;
    final index = int.tryParse(indexStr);
    if (index == null) return null;

    final citation = citations.firstWhere(
      (c) => c.index == index,
      orElse: () => Citation(index: index, rawId: '', sourceName: 'Source $index'),
    );

    return _InlineCitationWidget(citation: citation, onTap: () => onTap(citation));
  }
}

class _InlineCitationWidget extends StatelessWidget {
  final Citation citation;
  final VoidCallback onTap;

  const _InlineCitationWidget({
    required this.citation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      richMessage: WidgetSpan(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.description_outlined, color: colors.primary, size: 12),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      citation.sourceName,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (citation.snippet != null && citation.snippet!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  citation.snippet!,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 10,
                    height: 1.3,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E1E1E)
            : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      preferBelow: false,
      verticalOffset: 12,
      waitDuration: const Duration(milliseconds: 200),
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '[${citation.index}]',
              style: TextStyle(
                color: colors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: colors.primary.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
