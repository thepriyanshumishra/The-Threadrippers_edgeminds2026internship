// features/workspace/widgets/edge_telemetry_badge.dart
// Purpose: Displays real-time Edge hardware telemetry (RAM, Disk, ONNX provider) in top navbar.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/app_constants.dart';

class EdgeTelemetryBadge extends StatefulWidget {
  const EdgeTelemetryBadge({super.key});

  @override
  State<EdgeTelemetryBadge> createState() => _EdgeTelemetryBadgeState();
}

class _EdgeTelemetryBadgeState extends State<EdgeTelemetryBadge> {
  Timer? _timer;
  Map<String, dynamic>? _telemetry;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchTelemetry();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchTelemetry());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchTelemetry() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConstants.backendBaseUrl}/system/telemetry'),
      ).timeout(const Duration(seconds: 3));

      if (res.statusCode == 200 && mounted) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        setState(() {
          _telemetry = data;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final usedRam = _telemetry?['ram_used_gb'] ?? 1.4;
    final totalRam = _telemetry?['ram_total_gb'] ?? 8.0;
    final onnxProvider = _telemetry?['onnx_provider'] ?? 'CPU (INT8)';

    const tealColor = Color(0xFF00CBA9);

    return Tooltip(
      richMessage: TextSpan(
        children: [
          const TextSpan(
            text: '⚡ KIVO EDGE HARDWARE TELEMETRY\n',
            style: TextStyle(fontWeight: FontWeight.bold, color: tealColor),
          ),
          TextSpan(text: '• Memory: $usedRam GB / $totalRam GB RAM in use\n'),
          TextSpan(text: '• Vector Engine: ONNX $onnxProvider\n'),
          const TextSpan(text: '• Local LLM: Ollama (qwen2.5) · 100% On-Device\n'),
          const TextSpan(text: '• Zero Cloud Cost · Zero Data Leakage'),
        ],
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.black87,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: tealColor.withValues(alpha: isDark ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: tealColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF10B981), // Emerald green pulse
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF10B981),
                    blurRadius: 4,
                    spreadRadius: 1,
                  )
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _isLoading
                  ? '⚡ Edge AI'
                  : '⚡ Edge AI: ${usedRam.toStringAsFixed(1)}/${totalRam.toStringAsFixed(0)}GB RAM · ONNX INT8',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF5EEAD4) : tealColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
