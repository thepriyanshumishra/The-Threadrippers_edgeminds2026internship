// features/tutorial/screens/tutorial_overlay.dart
// Purpose: Renders a dark mask over the screen with a cutout highlighting the target widget, and displays a tooltip card.

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class TutorialOverlay extends StatefulWidget {
  final GlobalKey targetKey;
  final String title;
  final String description;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final String nextLabel;
  final Widget child;

  const TutorialOverlay({
    super.key,
    required this.targetKey,
    required this.title,
    required this.description,
    required this.onNext,
    required this.onSkip,
    this.nextLabel = 'Next',
    required this.child,
  });

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  Rect? _cutoutRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateCutout();
    });
  }

  @override
  void didUpdateWidget(covariant TutorialOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateCutout();
    });
  }
  void _calculateCutout() {
    if (!mounted) return;
    
    final targetContext = widget.targetKey.currentContext;
    if (targetContext == null) return;

    final RenderBox? box = targetContext.findRenderObject() as RenderBox?;
    if (box == null) return;

    final RenderBox? overlayBox = context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;

    final size = box.size;
    
    // Convert target local position to overlay local position instead of global position
    Offset position;
    try {
      position = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    } catch (_) {
      position = box.localToGlobal(Offset.zero);
    }

    setState(() {
      // Add padding around highlighted widget
      _cutoutRect = Rect.fromLTWH(
        position.dx - 8,
        position.dy - 8,
        size.width + 16,
        size.height + 16,
      );
    });
  }
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = MediaQuery.of(context).size;

    return Stack(
      children: [
        // 1. Screen Child
        widget.child,

        // 2. Dimmed Cutout Overlay
        if (_cutoutRect != null) ...[
          Positioned.fill(
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.black54,
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  // Dimmed full-screen cover
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  // Transparent hole cutout
                  Positioned.fromRect(
                    rect: _cutoutRect!,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Highlight Border Ring
          Positioned.fromRect(
            rect: _cutoutRect!,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: colors.primary, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),

          // 4. Tooltip Bubble Placement
          _buildTooltipBubble(size, colors),
        ],
      ],
    );
  }

  Widget _buildTooltipBubble(Size screenSize, AppColors colors) {
    final rect = _cutoutRect!;
    
    // Determine vertical placement
    final spaceBelow = screenSize.height - rect.bottom;
    final showBelow = spaceBelow > 180;
    
    final double top = showBelow ? rect.bottom + 12 : rect.top - 180;
    
    // Determine horizontal placement (center align relative to cutout, within bounds)
    double left = rect.left + (rect.width / 2) - 150;
    if (left < 16) left = 16;
    if (left + 300 > screenSize.width) left = screenSize.width - 316;

    return Positioned(
      top: top,
      left: left,
      width: 300,
      child: Card(
        color: colors.sidebarBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.border),
        ),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.description,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: widget.onSkip,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.textMuted,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(50, 30),
                    ),
                    child: const Text('Skip tutorial', style: TextStyle(fontSize: 11.5)),
                  ),
                  ElevatedButton(
                    onPressed: widget.onNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      minimumSize: const Size(60, 30),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    child: Text(widget.nextLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
