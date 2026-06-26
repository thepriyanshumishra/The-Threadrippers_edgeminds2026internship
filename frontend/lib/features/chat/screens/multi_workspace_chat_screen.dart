import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../workspace/providers/workspace_providers.dart';
import '../models/chat_message.dart';
import '../models/citation.dart';
import '../providers/chat_providers.dart';

class MultiWorkspaceChatScreen extends ConsumerStatefulWidget {
  const MultiWorkspaceChatScreen({super.key});

  @override
  ConsumerState<MultiWorkspaceChatScreen> createState() => _MultiWorkspaceChatScreenState();
}

class _MultiWorkspaceChatScreenState extends ConsumerState<MultiWorkspaceChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  
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
  }
  
  bool _isScopeExpanded = true;
  bool _isStrictSourceMode = true;
  final Set<String> _selectedWorkspaceIds = {};
  bool _hasInitializedWorkspaces = false;

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

    if (_selectedWorkspaceIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one workspace to search.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _messageController.clear();
    ref.read(universalChatProvider.notifier).sendUniversalMessage(
          _selectedWorkspaceIds.toList(),
          text,
          isStrict: _isStrictSourceMode,
        );
    _focusNode.requestFocus();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Watch workspaces list
    final workspacesAsync = ref.watch(workspacesProvider);
    final chatState = ref.watch(universalChatProvider);

    // Initialize selection with all workspaces
    workspacesAsync.whenData((list) {
      if (!_hasInitializedWorkspaces) {
        _selectedWorkspaceIds.addAll(list.map((w) => w.id));
        _hasInitializedWorkspaces = true;
      }
    });

    // Listen for error messages
    ref.listen<ChatState>(universalChatProvider, (previous, next) {
      if (next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: colors.statusFailed,
            behavior: SnackBarBehavior.floating,
          ),
        );
        ref.read(universalChatProvider.notifier).clearError();
      }
      if (next.messages.length > (previous?.messages.length ?? 0)) {
        _scrollToBottom();
      }
    });

    final selectedCount = _selectedWorkspaceIds.length;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, size: 18, color: colors.textSecondary),
          tooltip: 'All Workspaces',
          onPressed: () => context.go('/'),
        ),
        title: Text(
          'Universal Search',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: colors.divider),
        ),
      ),
      body: Column(
        children: [
          // Scope Checklist Card
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 24, 36, 12),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF202020) : Colors.white,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  // Card Header Row
                  InkWell(
                    onTap: () {
                      setState(() {
                        _isScopeExpanded = !_isScopeExpanded;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.manage_search_rounded, size: 18, color: colors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Universal Search Scope',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFF1F1EF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '$selectedCount Selected',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            _isScopeExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                            size: 18,
                            color: colors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Expanded grid panel
                  if (_isScopeExpanded) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: workspacesAsync.when(
                        data: (workspaces) {
                          if (workspaces.isEmpty) {
                            return Center(
                              child: Text(
                                'No workspaces available. Create a workspace first.',
                                style: TextStyle(color: colors.textMuted, fontSize: 13),
                              ),
                            );
                          }
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 20,
                              mainAxisSpacing: 12,
                              childAspectRatio: 4.5,
                            ),
                            itemCount: workspaces.length,
                            itemBuilder: (context, index) {
                              final ws = workspaces[index];
                              final isSelected = _selectedWorkspaceIds.contains(ws.id);
                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Checkbox(
                                      value: isSelected,
                                      activeColor: colors.primary,
                                      onChanged: (val) {
                                        setState(() {
                                          if (val == true) {
                                            _selectedWorkspaceIds.add(ws.id);
                                          } else {
                                            _selectedWorkspaceIds.remove(ws.id);
                                          }
                                        });
                                      },
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            ws.name,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: colors.textPrimary,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '${ws.sourcesCount} sources',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: colors.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                        loading: () => const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        error: (err, _) => Center(
                          child: Text(
                            'Error loading workspaces: $err',
                            style: TextStyle(color: colors.statusFailed, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Messages View
          Expanded(
            child: chatState.messages.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
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

          // Chat Input Controls
          Container(
            padding: const EdgeInsets.fromLTRB(36, 12, 36, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mode Toggle Capsule Row
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
                
                // TextInput Box
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF202020) : const Color(0xFFFBFBFA),
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.attach_file_rounded, size: 18, color: colors.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          focusNode: _focusNode,
                          minLines: 1,
                          maxLines: 5,
                          style: TextStyle(color: colors.textPrimary, fontSize: 13.5),
                          decoration: InputDecoration(
                            hintText: 'Ask across all selected workspaces...',
                            hintStyle: TextStyle(color: colors.textMuted, fontSize: 13.5),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Scope indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.layers_outlined, size: 12, color: colors.primary),
                            const SizedBox(width: 4),
                            Text(
                              'Universal Scope ($selectedCount)',
                              style: TextStyle(
                                color: colors.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: chatState.isStreaming
                            ? () {
                                ref.read(universalChatProvider.notifier).stopAddressing();
                              }
                            : _sendMessage,
                        icon: chatState.isStreaming
                            ? const Icon(Icons.stop_rounded, size: 16, color: Colors.white)
                            : const Icon(Icons.arrow_upward_rounded, size: 16, color: Colors.white),
                        style: IconButton.styleFrom(
                          backgroundColor: chatState.isStreaming ? colors.statusFailed : colors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
        color: isActive ? colors.primary.withValues(alpha: 0.1) : Colors.transparent,
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
              'Ask anything across multiple workspaces',
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
                  label: '✦ Summarize all files',
                  onTap: () {
                    _messageController.text = 'Summarize references across all my selected workspaces.';
                    _sendMessage();
                  },
                ),
                _QuickActionChip(
                  label: '✦ Find misalignments',
                  onTap: () {
                    _messageController.text = 'Are there any misalignments between technical plans and customer feedback?';
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

    if (!message.isUser && message.text.isEmpty) {
      return _buildSkeletonBubble(context);
    }

    final isStreaming = isLast && !message.isUser && message.citations.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Row(
            mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!message.isUser) ...[
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'K',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Kivo Copilot',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
          const SizedBox(height: 4),
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
                : SelectableText(
                    message.text,
                    style: textStyle,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
        color: isDark
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

