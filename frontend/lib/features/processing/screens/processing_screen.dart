import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../source_upload/providers/source_providers.dart';
import '../../workspace/providers/workspace_providers.dart';
import '../models/processing_status.dart';
import '../providers/processing_providers.dart';
import '../../../core/theme/theme_provider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants/app_constants.dart';
import '../services/processing_service.dart';


class ProcessingScreen extends ConsumerStatefulWidget {
  final String workspaceId;

  const ProcessingScreen({super.key, required this.workspaceId});

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  Timer? _timer;
  String? _lastStep;
  int _secondsRemaining = 0;

  static const Map<String, int> _stepDurations = {
    'pdf_extraction': 10,
    'image_ocr': 15,
    'audio_transcription': 45,
    'youtube_transcription': 30,
    'website_extraction': 12,
    'text_extraction': 4,
    'email_extraction': 4,
    'embedding_generation': 20,
    'building_knowledge_base': 8,
  };

  static const Map<String, String> _stepTitles = {
    'pdf_extraction': 'PDF Text Extraction',
    'image_ocr': 'Image OCR Processing',
    'audio_transcription': 'Audio Transcription (Whisper)',
    'youtube_transcription': 'YouTube Video Ingestion',
    'website_extraction': 'Website Link Extraction',
    'text_extraction': 'Plain Text Parsing',
    'email_extraction': 'Email Message Ingestion',
    'embedding_generation': 'Generating Search Embeddings',
    'building_knowledge_base': 'Compiling Knowledge Base',
  };

  static const Map<String, String> _stepDescriptions = {
    'pdf_extraction': 'Extracting layout text from PDFs...',
    'image_ocr': 'Running Tesseract OCR on images...',
    'audio_transcription': 'Transcribing audio track using Whisper...',
    'youtube_transcription': 'Fetching YouTube video audio and text...',
    'website_extraction': 'Extracting structured content from webpage...',
    'text_extraction': 'Importing plain text content...',
    'email_extraction': 'Parsing email message headers and body...',
    'embedding_generation': 'Vectorizing chunks using SentenceTransformers...',
    'building_knowledge_base': 'Indexing vectors into SQLite & FAISS...',
  };

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining > 1) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusState = ref.watch(processingStatusProvider(widget.workspaceId));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final workspaceState = ref.watch(activeWorkspaceProvider(widget.workspaceId));
    final workspaceName = workspaceState.maybeWhen(data: (w) => w.name, orElse: () => 'Workspace');

    // Listen for completion or failure to reload workspace and redirect/notify
    ref.listen<AsyncValue<ProcessingStatus>>(processingStatusProvider(widget.workspaceId), (prev, next) {
      next.whenData((data) {
        if (data.isFailed) {
          _timer?.cancel();
          _timer = null;

          if (data.errorType == 'deps_required' && data.missingPackages != null && data.missingPackages!.isNotEmpty) {
            _showDepsInstallationDialog(context, data.missingPackages!);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Workspace processing failed. Check backend logs.'),
                backgroundColor: colors.statusFailed,
              ),
            );
          }
          return;
        }

        if (data.isReady) {
          ref.invalidate(sourcesProvider(widget.workspaceId));
          ref.read(workspacesProvider.notifier).loadWorkspaces();
          _timer?.cancel();
          _timer = null;
          
          // Trigger system notification if enabled
          final notificationsOn = ref.read(notificationsEnabledProvider);
          if (notificationsOn && !kIsWeb) {
            try {
              if (Platform.isMacOS) {
                Process.run('osascript', [
                  '-e',
                  'display notification "Workspace ingestion is complete and ready for query." with title "Kivo Workspace" subtitle "$workspaceName" sound name "Glass"'
                ]);
              } else if (Platform.isWindows) {
                Process.run('powershell', [
                  '-Command',
                  'Add-Type -AssemblyName System.Windows.Forms; \$bal = New-Object System.Windows.Forms.NotifyIcon; \$bal.Icon = [System.Drawing.SystemIcons]::Information; \$bal.BalloonTipTitle = "Kivo Workspace"; \$bal.BalloonTipText = "Workspace ingestion is complete and ready for query: $workspaceName"; \$bal.Visible = \$true; \$bal.ShowBalloonTip(5000)'
                ]);
              } else if (Platform.isLinux) {
                Process.run('notify-send', [
                  'Kivo Workspace',
                  'Workspace ingestion is complete and ready for query: $workspaceName'
                ]);
              }
            } catch (e) {
              debugPrint('Failed to trigger OS notification: $e');
            }
          }

          // Automatically redirect to the chat screen
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              context.go(AppRoutes.workspace.replaceAll(':workspaceId', widget.workspaceId));
            }
          });
        }
      });
    });

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, size: 18, color: colors.textSecondary),
          tooltip: 'Dashboard',
          onPressed: () => context.go('/'),
        ),
        title: Row(
          children: [
            GestureDetector(
              onTap: () => context.go('/'),
              child: Text('Dashboard', style: TextStyle(fontSize: 13, color: colors.textSecondary)),
            ),
            Icon(Icons.chevron_right, size: 16, color: colors.textMuted),
            Text(workspaceName, style: TextStyle(fontSize: 13, color: colors.textSecondary)),
            Icon(Icons.chevron_right, size: 16, color: colors.textMuted),
            Text('Indexing', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textPrimary)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: colors.divider),
        ),
      ),
      body: statusState.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded, size: 40, color: colors.statusFailed),
              const SizedBox(height: 16),
              Text('Error loading processing pipeline', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(error.toString(), style: TextStyle(color: colors.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(processingStatusProvider(widget.workspaceId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (status) {
          final int progressPercent = (status.progress * 100).round();
          final isReady = status.isReady;

          // Manage the countdown timer on change of step
          if (status.currentStep != null && status.currentStep != _lastStep) {
            _lastStep = status.currentStep;
            _secondsRemaining = _stepDurations[status.currentStep] ?? 10;
            _startTimer();
          }

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 580),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF202020) : Colors.white,
                  border: Border.all(color: colors.border, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pipeline Header
                    Center(
                      child: Column(
                        children: [
                          Text(
                            'Processing Pipeline',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isReady 
                                ? 'Knowledge base compiled and ready!' 
                                : 'Background processing is active. You can safely navigate away.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Overall Progress Block
                    Row(
                      children: [
                        Text(
                          'Overall Progress',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'IBM Plex Mono',
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$progressPercent%',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'IBM Plex Mono',
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: status.progress,
                        minHeight: 6,
                        backgroundColor: isDark ? const Color(0xFF191919) : const Color(0xFFF1F1EF),
                        valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),

                    // STAGES
                    Text(
                      'PIPELINE STAGES',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'IBM Plex Mono',
                        fontWeight: FontWeight.w600,
                        color: colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Render dynamic stages from status.steps
                    if (status.steps.isEmpty)
                      Text(
                        'No processing steps queued.',
                        style: TextStyle(fontSize: 13, color: colors.textSecondary, fontStyle: FontStyle.italic),
                      )
                    else
                      Column(
                        children: status.steps.map((step) {
                          final isCompleted = status.completedSteps.contains(step);
                          final isActive = !isCompleted && status.currentStep == step;
                          
                          // Determine user friendly texts
                          final title = _stepTitles[step] ?? step;
                          final description = _stepDescriptions[step] ?? '';
                          
                          IconData iconData;
                          Color iconColor;
                          String subtitle;

                          if (isCompleted) {
                            iconData = Icons.check_circle_rounded;
                            iconColor = colors.statusReady;
                            subtitle = 'Completed';
                          } else if (isActive) {
                            iconData = Icons.sync;
                            iconColor = Colors.orange;
                            subtitle = '$description (~${_secondsRemaining}s remaining)';
                          } else {
                            iconData = Icons.radio_button_unchecked_rounded;
                            iconColor = colors.textMuted;
                            subtitle = 'Waiting in queue...';
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildStageCard(
                              context: context,
                              icon: iconData,
                              iconColor: iconColor,
                              title: title,
                              subtitle: subtitle,
                              isActive: isActive,
                              isCompleted: isCompleted,
                            ),
                          );
                        }).toList(),
                      ),

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 20),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => context.go('/'),
                            icon: const Icon(Icons.dashboard_outlined, size: 14),
                            label: const Text('Back to Dashboard'),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: colors.border),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              context.go(AppRoutes.workspace.replaceAll(':workspaceId', widget.workspaceId));
                            },
                            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
                            label: const Text('Open Chat Workspace'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStageCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isActive,
    required bool isCompleted,
  }) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bg;
    Border border;

    if (isActive) {
      bg = isDark ? const Color(0xFF1B2A32) : const Color(0xFFE7F3F8);
      border = Border.all(color: colors.primary.withValues(alpha: 0.5), width: 1.5);
    } else if (isCompleted) {
      bg = isDark ? const Color(0xFF222822) : const Color(0xFFEDF3EC);
      border = Border.all(color: colors.border);
    } else {
      bg = Colors.transparent;
      border = Border.all(color: colors.border, style: BorderStyle.solid);
    }

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: border,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isCompleted ? colors.textPrimary : (isActive ? colors.primary : colors.textSecondary),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isCompleted ? colors.textSecondary : colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDepsInstallationDialog(BuildContext context, List<String> missingDeps) {
    final colors = context.colors;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        bool isInstalling = false;
        String statusText = 'Kivo requires additional dependencies to process this file: ${missingDeps.join(', ')}. Would you like to install them now?';
        String installLog = '';

        return StatefulBuilder(
          builder: (stateCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(dialogCtx).scaffoldBackgroundColor,
              title: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Dependency Required',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(dialogCtx).textTheme.titleLarge?.color,
                    ),
                  ),
                ],
              ),
              content: Container(
                constraints: const BoxConstraints(maxWidth: 450),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(dialogCtx).textTheme.bodyMedium?.color,
                      ),
                    ),
                    if (isInstalling) ...[
                      const SizedBox(height: 16),
                      const Center(
                        child: SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      if (installLog.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          height: 120,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Theme.of(dialogCtx).brightness == Brightness.dark
                                ? const Color(0xFF151515)
                                : const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Theme.of(dialogCtx).brightness == Brightness.dark
                                  ? const Color(0xFF252525)
                                  : const Color(0xFFE5E5E5),
                            ),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: SingleChildScrollView(
                            child: Text(
                              installLog,
                              style: TextStyle(
                                fontSize: 10,
                                fontFamily: 'IBM Plex Mono',
                                color: Theme.of(dialogCtx).brightness == Brightness.dark
                                    ? Colors.white70
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              actions: [
                if (!isInstalling) ...[
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      setDialogState(() {
                        isInstalling = true;
                        statusText = 'Installing ${missingDeps.join(', ')}... This may take a minute.';
                      });

                      try {
                        final client = http.Client();
                        final url = Uri.parse('${AppConstants.backendBaseUrl}/system/install-deps');
                        final request = http.Request('POST', url)
                          ..headers['Content-Type'] = 'application/json'
                          ..body = json.encode({'deps': missingDeps});

                        final response = await client.send(request);

                        if (response.statusCode == 200) {
                          await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
                            if (line.trim().startsWith('data:')) {
                              try {
                                final dataJson = json.decode(line.substring(5).trim());
                                final lineText = dataJson['line'] as String?;
                                if (lineText != null) {
                                  setDialogState(() {
                                    installLog += '$lineText\n';
                                  });
                                }
                              } catch (_) {}
                            }
                          }

                          setDialogState(() {
                            statusText = 'Installation complete! Restarting processing...';
                          });
                          
                          await ref.read(processingServiceProvider).startProcessing(widget.workspaceId);
                          
                          if (dialogCtx.mounted) {
                            Navigator.of(dialogCtx).pop();
                          }
                          
                          ref.invalidate(processingStatusProvider(widget.workspaceId));
                        } else {
                          setDialogState(() {
                            isInstalling = false;
                            statusText = 'Installation failed. Status: ${response.statusCode}';
                          });
                        }
                      } catch (e) {
                        setDialogState(() {
                          isInstalling = false;
                          statusText = 'Error during installation: $e';
                        });
                      }
                    },
                    child: const Text('Install Now'),
                  ),
                ] else ...[
                  if (!statusText.contains('complete') && !statusText.contains('Restarting') && !statusText.contains('Installing'))
                    TextButton(
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                      child: const Text('Close'),
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
