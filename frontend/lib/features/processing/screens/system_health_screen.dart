import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../models/system_diagnostics.dart';
import '../services/system_health_service.dart';

class SystemHealthScreen extends ConsumerStatefulWidget {
  const SystemHealthScreen({super.key});

  @override
  ConsumerState<SystemHealthScreen> createState() => _SystemHealthScreenState();
}

class _SystemHealthScreenState extends ConsumerState<SystemHealthScreen> with SingleTickerProviderStateMixin {
  bool _isRefreshing = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _triggerDiagnostics() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });

    try {
      final future = ref.refresh(systemDiagnosticsProvider.future);
      await future;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Diagnostics completed successfully.',
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
              'Failed to rerun diagnostics: $e',
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
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final diagnosticsState = ref.watch(systemDiagnosticsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, size: 18, color: colors.textSecondary),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'System Health',
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
      body: SafeArea(
        child: Column(
          children: [
            // Top Action Header
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
                        'System Diagnostics',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Real-time status of critical RAG pipeline services.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: _isRefreshing ? null : _triggerDiagnostics,
                    icon: _isRefreshing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded, size: 14),
                    label: Text(_isRefreshing ? 'Running...' : 'Re-Run Diagnostics'),
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

            // Diagnostics Content
            Expanded(
              child: diagnosticsState.when(
                loading: () => _buildLoadingState(context),
                error: (error, stack) => _buildErrorState(context, error, _triggerDiagnostics),
                data: (diagnostics) => _buildContentState(context, diagnostics),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentState(BuildContext context, SystemDiagnostics diagnostics) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Summary Card
        _buildSummaryCard(context, diagnostics),
        const SizedBox(height: 24),

        // Grid / Wrap layout for services
        LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth > 700;
            if (isDesktop) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildTesseractCard(context, diagnostics.tesseract)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildFFmpegCard(context, diagnostics.ffmpeg)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildOllamaCard(context, diagnostics.ollama)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildDatabaseCard(context, diagnostics.database)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildStorageCard(context, diagnostics.storage),
                ],
              );
            } else {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTesseractCard(context, diagnostics.tesseract),
                  const SizedBox(height: 16),
                  _buildFFmpegCard(context, diagnostics.ffmpeg),
                  const SizedBox(height: 16),
                  _buildOllamaCard(context, diagnostics.ollama),
                  const SizedBox(height: 16),
                  _buildDatabaseCard(context, diagnostics.database),
                  const SizedBox(height: 16),
                  _buildStorageCard(context, diagnostics.storage),
                ],
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildSummaryCard(BuildContext context, SystemDiagnostics diagnostics) {
    final colors = context.colors;

    int errors = 0;
    int warnings = 0;

    void check(ServiceStatus s) {
      if (s.isOffline) errors++;
      if (s.isWarning) warnings++;
    }

    check(diagnostics.tesseract);
    check(diagnostics.ffmpeg);
    check(diagnostics.ollama);
    check(diagnostics.database);
    check(diagnostics.storage);

    Color cardColor;
    Color borderColor;
    Color iconColor;
    IconData icon;
    String title;
    String subtitle;

    if (errors > 0) {
      cardColor = colors.statusFailedBg;
      borderColor = colors.statusFailed.withValues(alpha: 0.3);
      iconColor = colors.statusFailed;
      icon = Icons.error_outline_rounded;
      title = 'System Configuration Issues Detected';
      subtitle = 'One or more critical offline processing components are unreachable. Some functionalities might fail.';
    } else if (warnings > 0) {
      cardColor = colors.statusProcessingBg;
      borderColor = colors.statusProcessing.withValues(alpha: 0.3);
      iconColor = colors.statusProcessing;
      icon = Icons.warning_amber_rounded;
      title = 'System Warnings';
      subtitle = 'Dependencies are online, but some minor issues require attention.';
    } else {
      cardColor = colors.statusReadyBg;
      borderColor = colors.statusReady.withValues(alpha: 0.3);
      iconColor = colors.statusReady;
      icon = Icons.check_circle_outline_rounded;
      title = 'All Systems Operational';
      subtitle = 'Kivo is fully configured for offline, edge-first processing with OCR, transcription, database, and LLM services active.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTesseractCard(BuildContext context, ServiceStatus status) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final latency = status.metadata['latency'] as String? ?? 'N/A';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF202020) : Colors.white,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.document_scanner_outlined, size: 18, color: colors.textSecondary),
                  const SizedBox(width: 10),
                  Text(
                    'Tesseract OCR',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              _buildStatusPill(context, status),
            ],
          ),
          const SizedBox(height: 14),
          _buildDetailItem(context, 'Service Type', 'Image Text Extraction'),
          const SizedBox(height: 8),
          _buildDetailItem(context, 'Execution Latency', latency),
          const SizedBox(height: 8),
          _buildDetailItem(context, 'Binary Version', status.version),
          if (status.isOffline) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.statusFailedBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colors.statusFailed.withValues(alpha: 0.15)),
              ),
              child: Text(
                'OCR will fail. Install Tesseract OCR to resolve this issue.',
                style: TextStyle(fontSize: 10.5, color: colors.statusFailed, height: 1.3),
              ),
            )
          ],
        ],
      ),
    );
  }

  Widget _buildFFmpegCard(BuildContext context, ServiceStatus status) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final queue = status.metadata['queue'] as String? ?? '0 items';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF202020) : Colors.white,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.movie_outlined, size: 18, color: colors.textSecondary),
                  const SizedBox(width: 10),
                  Text(
                    'FFmpeg Processor',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              _buildStatusPill(context, status),
            ],
          ),
          const SizedBox(height: 14),
          _buildDetailItem(context, 'Service Type', 'Audio & Video Transcoding'),
          const SizedBox(height: 8),
          _buildDetailItem(context, 'Task Queue', queue),
          const SizedBox(height: 8),
          _buildDetailItem(context, 'Binary Version', status.version),
          if (status.isOffline) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.statusFailedBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colors.statusFailed.withValues(alpha: 0.15)),
              ),
              child: Text(
                'Audio transcription will fail. Install FFmpeg to resolve this issue.',
                style: TextStyle(fontSize: 10.5, color: colors.statusFailed, height: 1.3),
              ),
            )
          ],
        ],
      ),
    );
  }

  Widget _buildOllamaCard(BuildContext context, ServiceStatus status) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final defaultModel = status.metadata['default_model'] as String? ?? 'qwen2.5:1.5b';
    final isModelAvailable = status.metadata['is_model_available'] as bool? ?? false;
    final availableModels = List<String>.from(status.metadata['available_models'] ?? []);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF202020) : Colors.white,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.smart_toy_outlined, size: 18, color: colors.textSecondary),
                  const SizedBox(width: 10),
                  Text(
                    'Ollama LLM Service',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              _buildStatusPill(context, status),
            ],
          ),
          const SizedBox(height: 14),
          _buildDetailItem(context, 'Configured Model', defaultModel),
          const SizedBox(height: 8),
          _buildDetailItem(
            context,
            'Model Status',
            isModelAvailable ? 'Ready' : (status.isOnline ? 'Not Pulled' : 'Offline'),
            valueColor: isModelAvailable ? colors.statusReady : (status.isOnline ? colors.statusProcessing : colors.statusFailed),
            valueWeight: FontWeight.w700,
          ),
          const SizedBox(height: 12),
          Text(
            'Pulled Models',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          if (availableModels.isEmpty)
            Text(
              'No models pulled yet.',
              style: TextStyle(
                fontSize: 11.5,
                color: colors.textMuted,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: availableModels.map((model) {
                final isDefault = model.contains(defaultModel);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDefault 
                        ? colors.primary.withValues(alpha: 0.1) 
                        : (isDark ? const Color(0xFF2D2D2D) : const Color(0xFFF1F1EF)),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isDefault 
                          ? colors.primary.withValues(alpha: 0.3) 
                          : colors.border,
                    ),
                  ),
                  child: Text(
                    model,
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
                      color: isDefault ? colors.primary : colors.textSecondary,
                      fontWeight: isDefault ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildDatabaseCard(BuildContext context, ServiceStatus status) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final engine = status.metadata['engine'] as String? ?? 'SQLite & FAISS';
    final collections = status.metadata['collections'] as int? ?? 0;
    final totalEmbeddings = status.metadata['total_embeddings'] as int? ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF202020) : Colors.white,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.storage_outlined, size: 18, color: colors.textSecondary),
                  const SizedBox(width: 10),
                  Text(
                    'Vector & Metadata DB',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              _buildStatusPill(context, status),
            ],
          ),
          const SizedBox(height: 14),
          _buildDetailItem(context, 'Database Engine', engine),
          const SizedBox(height: 8),
          _buildDetailItem(context, 'Total Collections', collections.toString()),
          const SizedBox(height: 8),
          _buildDetailItem(
            context,
            'Total Embeddings',
            _formatNumber(totalEmbeddings),
          ),
          const SizedBox(height: 8),
          _buildDetailItem(context, 'Engine Details', status.version),
        ],
      ),
    );
  }

  Widget _buildStorageCard(BuildContext context, ServiceStatus status) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final path = status.metadata['path'] as String? ?? 'N/A';
    final percent = (status.metadata['percent'] as num? ?? 0.0).toDouble();
    final usedGb = (status.metadata['used_gb'] as num? ?? 0.0).toDouble();
    final freeGb = (status.metadata['free_gb'] as num? ?? 0.0).toDouble();
    final totalGb = (status.metadata['total_gb'] as num? ?? 0.0).toDouble();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF202020) : Colors.white,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.dns_outlined, size: 18, color: colors.textSecondary),
                  const SizedBox(width: 10),
                  Text(
                    'Local Storage Volume',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              _buildStatusPill(context, status),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Disk Usage',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              Text(
                '${percent.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 6,
              backgroundColor: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFF1F1EF),
              valueColor: AlwaysStoppedAnimation<Color>(
                percent > 90 
                    ? colors.statusFailed 
                    : (percent > 75 ? colors.statusProcessing : colors.primary),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildDetailItem(context, 'Storage Path', path),
          const SizedBox(height: 8),
          _buildDetailItem(context, 'Space Used', '${usedGb.toStringAsFixed(1)} GB'),
          const SizedBox(height: 8),
          _buildDetailItem(context, 'Space Free', '${freeGb.toStringAsFixed(1)} GB'),
          const SizedBox(height: 8),
          _buildDetailItem(context, 'Total Capacity', '${totalGb.toStringAsFixed(1)} GB'),
        ],
      ),
    );
  }

  Widget _buildStatusPill(BuildContext context, ServiceStatus status) {
    final colors = context.colors;

    Color bgColor;
    Color textColor;
    Color dotColor;

    if (status.isOnline) {
      bgColor = colors.statusReadyBg;
      textColor = colors.statusReady;
      dotColor = colors.statusReady;
    } else if (status.isWarning) {
      bgColor = colors.statusProcessingBg;
      textColor = colors.statusProcessing;
      dotColor = colors.statusProcessing;
    } else {
      bgColor = colors.statusFailedBg;
      textColor = colors.statusFailed;
      dotColor = colors.statusFailed;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: textColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: _pulseController,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status.status,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: textColor,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(
    BuildContext context, 
    String label, 
    String value, {
    Color? valueColor,
    FontWeight valueWeight = FontWeight.w600,
  }) {
    final colors = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
              fontWeight: valueWeight,
              color: valueColor ?? colors.textPrimary,
            ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatNumber(int number) {
    if (number < 1000) return number.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return number.toString().replaceAllMapped(reg, (Match m) => '${m[1]},');
  }

  Widget _buildLoadingState(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        _ShimmerCard(height: 80),
        SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: _ShimmerCard(height: 120)),
            SizedBox(width: 16),
            Expanded(child: _ShimmerCard(height: 120)),
          ],
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _ShimmerCard(height: 160)),
            SizedBox(width: 16),
            Expanded(child: _ShimmerCard(height: 160)),
          ],
        ),
        SizedBox(height: 16),
        _ShimmerCard(height: 150),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, Object error, VoidCallback onRetry) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF202020) : Colors.white,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: colors.statusFailed),
            const SizedBox(height: 16),
            Text(
              'Cannot Connect to Kivo Backend',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'The diagnostics service is unreachable. Please verify that the Kivo Workspace FastAPI server is running on localhost.',
              style: TextStyle(
                fontSize: 12.5,
                color: colors.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 14),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShimmerCard extends StatefulWidget {
  final double height;
  const _ShimmerCard({required this.height});

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.35, end: 0.75).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF202020) : Colors.white,
              border: Border.all(color: colors.border, width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      },
    );
  }
}
