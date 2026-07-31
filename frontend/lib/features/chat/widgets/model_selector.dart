import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../onboarding/models/onboarding_state.dart';

class ModelSelectorWidget extends StatefulWidget {
  final List<String> availableModels;
  final String selectedModel;
  final ValueChanged<String> onModelChanged;
  final VoidCallback onAddModel;

  const ModelSelectorWidget({
    super.key,
    required this.availableModels,
    required this.selectedModel,
    required this.onModelChanged,
    required this.onAddModel,
  });

  @override
  State<ModelSelectorWidget> createState() => _ModelSelectorWidgetState();
}

class _ModelSelectorWidgetState extends State<ModelSelectorWidget>
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

  String _getShortName(String modelId) {
    try {
      final curated = curatedModelRegistry.firstWhere((m) => m.id == modelId);
      final parts = curated.name.split(' ');
      if (parts.length > 2) {
        return '${parts[0]} ${parts[1]}';
      }
      return curated.name;
    } catch (_) {
      final parts = modelId.split(':');
      if (parts.isNotEmpty) {
        final name = parts.first;
        if (name.isEmpty) return modelId;
        return name.substring(0, 1).toUpperCase() + name.substring(1);
      }
      return modelId;
    }
  }

  String? _getVersionTag(String modelId) {
    final parts = modelId.split(':');
    if (parts.length > 1) return parts.last.toUpperCase();
    return null;
  }

  OverlayEntry _buildOverlay() {
    return OverlayEntry(
      builder: (context) {
        final colors = context.colors;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        const accent = Color(0xFFF59E0B);

        final items = widget.availableModels;
        final double offsetHeight = (items.length + 1) * 52.0 + 16.0;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeDropdown,
                behavior: HitTestBehavior.translucent,
                child: const SizedBox.expand(),
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(0, -offsetHeight),
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
                        children: [
                          ...items.map((modelId) {
                            final isSelected = modelId == widget.selectedModel;
                            final shortName = _getShortName(modelId);
                            final versionTag = _getVersionTag(modelId);

                            return GestureDetector(
                              onTap: () {
                                widget.onModelChanged(modelId);
                                _closeDropdown();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? accent.withValues(alpha: 0.12)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              shortName,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight:
                                                    isSelected ? FontWeight.w700 : FontWeight.w500,
                                                color: isSelected ? accent : colors.textPrimary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (versionTag != null) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 4, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? accent.withValues(alpha: 0.2)
                                                    : colors.border,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                versionTag,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: isSelected ? accent : colors.textSecondary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(Icons.check_rounded, size: 14, color: accent),
                                  ],
                                ),
                              ),
                            );
                          }),
                          GestureDetector(
                            onTap: () {
                              _closeDropdown();
                              widget.onAddModel();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.add, size: 16, color: Colors.blue),
                                  SizedBox(width: 8),
                                  Text(
                                    'Add Model',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
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
    const accent = Color(0xFFF59E0B);

    final hasModel = widget.availableModels.isNotEmpty && widget.selectedModel.isNotEmpty;
    final displayName = hasModel ? _getShortName(widget.selectedModel) : 'No model';
    final textColor = hasModel ? accent : colors.textMuted;

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
              const Text('🤖', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              Text(
                displayName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textColor,
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
