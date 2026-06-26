// core/utils/eyedropper_helper.dart
// Purpose: Multi-platform eyedropper and color picker helper.
// Provides native macOS eyedropper, native Windows color dialog, and interactive in-app eyedropper.

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

final GlobalKey appRepaintKey = GlobalKey();

class EyedropperHelper {
  static const _channel = MethodChannel('com.kivo.kivo_workspace/eyedropper');

  /// Pick a color using the best available eyedropper/selector for the platform.
  static Future<Color?> pickColor(BuildContext context) async {
    if (!kIsWeb) {
      // 1. For macOS: Use the native NSColorSampler (which picks inside & outside the app)
      if (Platform.isMacOS) {
        try {
          final String? hex = await _channel.invokeMethod('pickColor');
          if (hex != null) {
            return _parseHexColor(hex);
          }
          return null; // Cancelled
        } catch (e) {
          debugPrint('macOS native eyedropper failed: $e. Falling back to in-app.');
        }
      }

      // 2. For Windows: Try the native Win32 ChooseColor dialog, and fallback to in-app.
      if (Platform.isWindows) {
        try {
          final String? hex = await _channel.invokeMethod('pickColor');
          if (hex != null) {
            return _parseHexColor(hex);
          }
          return null; // Cancelled
        } catch (e) {
          debugPrint('Windows native color dialog failed: $e. Falling back to in-app.');
        }
      }
    }

    // 3. Fallback: Show the premium in-app interactive eyedropper
    if (!context.mounted) return null;
    return showInAppEyedropper(context);
  }

  static Color _parseHexColor(String hex) {
    String cleanHex = hex.replaceAll('#', '');
    if (cleanHex.length == 6) {
      cleanHex = 'FF$cleanHex';
    }
    return Color(int.parse(cleanHex, radix: 16));
  }

  /// Interactive screen eyedropper that captures the app window and lets the user pick a color with a magnifier.
  static Future<Color?> showInAppEyedropper(BuildContext context) async {
    try {
      // Find the repaint boundary
      final RenderRepaintBoundary? boundary =
          appRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot capture screen. RepaintBoundary not found.')),
        );
        return null;
      }

      // Capture screenshot at original scale
      final double pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (byteData == null) return null;

      // Push custom full-screen route with the interactive overlay
      if (!context.mounted) return null;
      return await Navigator.push<Color>(
        context,
        PageRouteBuilder(
          opaque: false,
          pageBuilder: (context, _, __) => EyedropperOverlay(
            image: image,
            byteData: byteData,
            pixelRatio: pixelRatio,
          ),
          transitionsBuilder: (context, animation, _, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } catch (e) {
      debugPrint('Error showing in-app eyedropper: $e');
      return null;
    }
  }
}

class EyedropperOverlay extends StatefulWidget {
  final ui.Image image;
  final ByteData byteData;
  final double pixelRatio;

  const EyedropperOverlay({
    super.key,
    required this.image,
    required this.byteData,
    required this.pixelRatio,
  });

  @override
  State<EyedropperOverlay> createState() => _EyedropperOverlayState();
}

class _EyedropperOverlayState extends State<EyedropperOverlay> {
  Offset _cursorPos = Offset.zero;
  Color _hoverColor = Colors.transparent;
  bool _hasMouse = false;

  @override
  Widget build(BuildContext context) {
    final width = widget.image.width;
    final height = widget.image.height;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MouseRegion(
        cursor: SystemMouseCursors.none, // Hide normal cursor in eyedropper mode
        onHover: (event) {
          final logicalPos = event.localPosition;
          final physicalX = (logicalPos.dx * widget.pixelRatio).round().clamp(0, width - 1);
          final physicalY = (logicalPos.dy * widget.pixelRatio).round().clamp(0, height - 1);

          final offset = (physicalY * width + physicalX) * 4;
          if (offset + 3 < widget.byteData.lengthInBytes) {
            final r = widget.byteData.getUint8(offset);
            final g = widget.byteData.getUint8(offset + 1);
            final b = widget.byteData.getUint8(offset + 2);
            final a = widget.byteData.getUint8(offset + 3);
            setState(() {
              _cursorPos = logicalPos;
              _hoverColor = Color.fromARGB(a, r, g, b);
              _hasMouse = true;
            });
          }
        },
        onExit: (_) {
          setState(() {
            _hasMouse = false;
          });
        },
        child: GestureDetector(
          onTapUp: (details) {
            final logicalPos = details.localPosition;
            final physicalX = (logicalPos.dx * widget.pixelRatio).round().clamp(0, width - 1);
            final physicalY = (logicalPos.dy * widget.pixelRatio).round().clamp(0, height - 1);

            final offset = (physicalY * width + physicalX) * 4;
            if (offset + 3 < widget.byteData.lengthInBytes) {
              final r = widget.byteData.getUint8(offset);
              final g = widget.byteData.getUint8(offset + 1);
              final b = widget.byteData.getUint8(offset + 2);
              final a = widget.byteData.getUint8(offset + 3);
              Navigator.pop(context, Color.fromARGB(a, r, g, b));
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Display screenshot full screen
              RawImage(
                image: widget.image,
                fit: BoxFit.fill,
              ),

              // Escape button to cancel
              Positioned(
                top: 40,
                right: 40,
                child: FloatingActionButton.small(
                  backgroundColor: Colors.black.withValues(alpha: 0.7),
                  foregroundColor: Colors.white,
                  onPressed: () => Navigator.pop(context),
                  child: const Icon(Icons.close),
                ),
              ),

              // Magnifier circular hover effect
              if (_hasMouse)
                Positioned(
                  left: _cursorPos.dx - 70,
                  top: _cursorPos.dy - 70,
                  child: IgnorePointer(
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 10,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: ClipOval(
                        child: CustomPaint(
                          painter: MagnifierPainter(
                            byteData: widget.byteData,
                            imageWidth: width,
                            imageHeight: height,
                            centerX: (_cursorPos.dx * widget.pixelRatio).round(),
                            centerY: (_cursorPos.dy * widget.pixelRatio).round(),
                            hoverColor: _hoverColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class MagnifierPainter extends CustomPainter {
  final ByteData byteData;
  final int imageWidth;
  final int imageHeight;
  final int centerX;
  final int centerY;
  final Color hoverColor;

  MagnifierPainter({
    required this.byteData,
    required this.imageWidth,
    required this.imageHeight,
    required this.centerX,
    required this.centerY,
    required this.hoverColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const int gridCount = 9; // Show 9x9 pixels
    const int halfGrid = gridCount ~/ 2;
    final double pixelSize = size.width / gridCount;

    // Draw the pixel grid
    for (int dy = -halfGrid; dy <= halfGrid; dy++) {
      for (int dx = -halfGrid; dx <= halfGrid; dx++) {
        final px = (centerX + dx).clamp(0, imageWidth - 1);
        final py = (centerY + dy).clamp(0, imageHeight - 1);

        final offset = (py * imageWidth + px) * 4;
        Color color = Colors.black;
        if (offset + 3 < byteData.lengthInBytes) {
          final r = byteData.getUint8(offset);
          final g = byteData.getUint8(offset + 1);
          final b = byteData.getUint8(offset + 2);
          final a = byteData.getUint8(offset + 3);
          color = Color.fromARGB(a, r, g, b);
        }

        final rect = Rect.fromLTWH(
          (dx + halfGrid) * pixelSize,
          (dy + halfGrid) * pixelSize,
          pixelSize,
          pixelSize,
        );

        final paint = Paint()..color = color;
        canvas.drawRect(rect, paint);

        // Subtle borders between pixels
        final borderPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;
        canvas.drawRect(rect, borderPaint);
      }
    }

    // Highlight center pixel
    final centerRect = Rect.fromLTWH(
      halfGrid * pixelSize,
      halfGrid * pixelSize,
      pixelSize,
      pixelSize,
    );
    final targetPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(centerRect, targetPaint);

    // Draw bottom label showing hex color
    final hexString = '#${hoverColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    final textPainter = TextPainter(
      text: TextSpan(
        text: hexString,
        style: TextStyle(
          color: hoverColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          backgroundColor: hoverColor.withValues(alpha: 0.8),
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        size.height - textPainter.height - 6,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant MagnifierPainter oldDelegate) {
    return oldDelegate.centerX != centerX || oldDelegate.centerY != centerY;
  }
}
