import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

enum ChatMode {
  strict,
  defaultMode,
  explore;

  String get apiValue {
    switch (this) {
      case ChatMode.strict:
        return 'strict';
      case ChatMode.defaultMode:
        return 'default';
      case ChatMode.explore:
        return 'explore';
    }
  }

  String get label {
    switch (this) {
      case ChatMode.strict:
        return 'Strict';
      case ChatMode.defaultMode:
        return 'Default';
      case ChatMode.explore:
        return 'Explore';
    }
  }

  String get description {
    switch (this) {
      case ChatMode.strict:
        return 'Answers only from your documents';
      case ChatMode.defaultMode:
        return 'Documents + AI knowledge';
      case ChatMode.explore:
        return 'Pure AI, no documents';
    }
  }

  String get emoji {
    switch (this) {
      case ChatMode.strict:
        return '🔒';
      case ChatMode.defaultMode:
        return '⚡';
      case ChatMode.explore:
        return '✨';
    }
  }

  Color accentColor(bool isDark) {
    switch (this) {
      case ChatMode.strict:
        return const Color(0xFF00CBA9);
      case ChatMode.defaultMode:
        return const Color(0xFF6366F1);
      case ChatMode.explore:
        return const Color(0xFFEC4899);
    }
  }
}

class ModeSelectorWidget extends StatefulWidget {
  final ChatMode selectedMode;
  final ValueChanged<ChatMode> onModeChanged;

  const ModeSelectorWidget({
    super.key,
    required this.selectedMode,
    required this.onModeChanged,
  });

  @override
  State<ModeSelectorWidget> createState() => _ModeSelectorWidgetState();
}

class _ModeSelectorWidgetState extends State<ModeSelectorWidget>
    with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _removeOverlay();
    _controller.dispose();
    super.dispose();
  }

  void _toggleDropdown() {
    if (_isOpen) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  void _openDropdown() {
    _overlayEntry = _buildOverlay();
    Overlay.of(context).insert(_overlayEntry!);
    _controller.forward();
    setState(() => _isOpen = true);
  }

  void _closeDropdown() {
    _controller.reverse().then((_) => _removeOverlay());
    setState(() => _isOpen = false);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _buildOverlay() {
    return OverlayEntry(
      builder: (context) {
        final colors = context.colors;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Stack(
          children: [
            // Backdrop dismiss
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeDropdown,
                behavior: HitTestBehavior.translucent,
                child: const SizedBox.expand(),
              ),
            ),
            // Dropdown positioned above the trigger
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, -168),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 240,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E3),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: ChatMode.values.map((mode) {
                          final isSelected = mode == widget.selectedMode;
                          final accent = mode.accentColor(isDark);
                          return GestureDetector(
                            onTap: () {
                              widget.onModeChanged(mode);
                              _closeDropdown();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? accent.withValues(alpha: 0.12)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Text(mode.emoji, style: const TextStyle(fontSize: 16)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          mode.label,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight:
                                                isSelected ? FontWeight.w700 : FontWeight.w500,
                                            color: isSelected ? accent : colors.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          mode.description,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: colors.textMuted,
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(Icons.check_rounded, size: 14, color: accent),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.selectedMode.accentColor(isDark);

    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: _toggleDropdown,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF252525) : const Color(0xFFF5F5F3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isOpen ? accent.withValues(alpha: 0.5) : colors.border,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.selectedMode.emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              Text(
                widget.selectedMode.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _isOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: colors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
