import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../models/source.dart';
import '../providers/source_providers.dart';
import '../../processing/services/processing_service.dart';
import '../../../core/router/app_router.dart';
import '../../workspace/providers/workspace_providers.dart';
import '../../../core/theme/theme_provider.dart';
import '../../tutorial/providers/tutorial_provider.dart';
import '../../tutorial/screens/tutorial_overlay.dart';

class SourceUploadScreen extends ConsumerStatefulWidget {
  final String workspaceId;

  const SourceUploadScreen({super.key, required this.workspaceId});

  @override
  ConsumerState<SourceUploadScreen> createState() => _SourceUploadScreenState();
}

class _SourceUploadScreenState extends ConsumerState<SourceUploadScreen> {
  bool _isLoading = false;

  String _formatSize(int? bytes) {
    if (bytes == null) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _computeTotalSize(List<Source> sources) {
    int total = 0;
    for (var s in sources) {
      total += s.sizeBytes ?? 0;
    }
    if (total == 0) return '0 B';
    return _formatSize(total);
  }

  Future<void> _pickFilesForType({
    required List<String> allowedExtensions,
    required String typeLabel,
  }) async {
    setState(() => _isLoading = true);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      for (var pickedFile in result.files) {
        List<int> bytes;
        if (pickedFile.bytes != null) {
          bytes = pickedFile.bytes!;
        } else if (pickedFile.path != null) {
          bytes = await File(pickedFile.path!).readAsBytes();
        } else {
          continue;
        }

        await ref.read(sourcesProvider(widget.workspaceId).notifier).uploadFile(
              bytes,
              pickedFile.name,
            );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully uploaded ${result.files.length} $typeLabel source(s)'),
            backgroundColor: context.colors.statusReady,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${e.toString()}'),
            backgroundColor: context.colors.statusFailed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _startProcessingPipeline() async {
    setState(() => _isLoading = true);
    try {
      final chunkSize = ref.read(ragChunkSizeProvider);
      final chunkOverlap = ref.read(ragChunkOverlapProvider);
      await ref.read(processingServiceProvider).startProcessing(
        widget.workspaceId,
        chunkSize: chunkSize,
        chunkOverlap: chunkOverlap,
      );
      if (mounted) {
        context.push(
          AppRoutes.processing.replaceAll(':workspaceId', widget.workspaceId),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start processing: ${e.toString()}'),
            backgroundColor: context.colors.statusFailed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildSourceCard({
    Key? key,
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
    String? subtext,
  }) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MouseRegion(
      key: key,
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF202020) : Colors.white,
            border: Border.all(color: colors.border, width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(icon, color: colors.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.textSecondary,
                ),
              ),
              if (subtext != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2D261E) : const Color(0xFFFDF6ED),
                    border: Border.all(
                      color: isDark ? const Color(0xFF5A442E) : const Color(0xFFF5E0C9),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi, color: isDark ? const Color(0xFFC79E73) : const Color(0xFFB37D4E), size: 10),
                      const SizedBox(width: 4),
                      Text(
                        subtext,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFFC79E73) : const Color(0xFFB37D4E),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sourcesState = ref.watch(sourcesProvider(widget.workspaceId));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tutorialState = ref.watch(tutorialProvider);

    final workspaceState = ref.watch(activeWorkspaceProvider(widget.workspaceId));
    final workspaceName = workspaceState.maybeWhen(data: (w) => w.name, orElse: () => 'Workspace');

    Widget body = Scaffold(
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
              child: Text(
                'Dashboard',
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: colors.textMuted),
            Text(
              workspaceName,
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
            Icon(Icons.chevron_right, size: 16, color: colors.textMuted),
            Text(
              'Add Sources',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textPrimary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.go('/'),
            child: Text(
              'Cancel',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: colors.divider),
        ),
      ),
      body: sourcesState.when(
          loading: () => const Center(child: CircularProgressIndicator.adaptive()),
          error: (error, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded, size: 40, color: colors.statusFailed),
                const SizedBox(height: 16),
                Text('Failed to load sources', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(error.toString(), style: TextStyle(color: colors.textSecondary)),
              ],
            ),
          ),
          data: (sources) {
            return SingleChildScrollView(
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 800),
                  padding: const EdgeInsets.fromLTRB(36, 28, 36, 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Page Title
                      Text(
                        'Add Sources',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Upload documents, paste URLs, or add media to begin indexing.',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),

                      GridView.count(
                        crossAxisCount: MediaQuery.of(context).size.width < 600 ? 1 : 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: MediaQuery.of(context).size.width < 600 ? 3.5 : 1.35,
                        children: [
                          _buildSourceCard(
                            key: TutorialKeys.pdfSourceCard,
                            context: context,
                            icon: Icons.picture_as_pdf_outlined,
                            title: 'PDF Document',
                            description: 'Upload standard PDF files',
                            onTap: () => _pickFilesForType(allowedExtensions: ['pdf'], typeLabel: 'PDF'),
                          ),
                          _buildSourceCard(
                            context: context,
                            icon: Icons.image_outlined,
                            title: 'Image File',
                            description: 'Upload images for OCR processing',
                            onTap: () => _pickFilesForType(
                              allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
                              typeLabel: 'Image',
                            ),
                          ),
                          _buildSourceCard(
                            context: context,
                            icon: Icons.language_outlined,
                            title: 'Website Link',
                            description: 'Import content from webpage URL',
                            subtext: 'Internet Needed',
                            onTap: () => showDialog(
                              context: context,
                              builder: (context) => _WebsiteUrlDialog(workspaceId: widget.workspaceId),
                            ),
                          ),
                          _buildSourceCard(
                            context: context,
                            icon: Icons.notes_outlined,
                            title: 'Copied Text',
                            description: 'Paste plain text directly',
                            onTap: () => showDialog(
                              context: context,
                              builder: (context) => _CopyTextDialog(workspaceId: widget.workspaceId),
                            ),
                          ),
                          _buildSourceCard(
                            context: context,
                            icon: Icons.play_circle_outline_rounded,
                            title: 'YouTube Video',
                            description: 'Fetch video transcript from URL',
                            subtext: 'Internet Needed',
                            onTap: () => showDialog(
                              context: context,
                              builder: (context) => _YouTubeUrlDialog(workspaceId: widget.workspaceId),
                            ),
                          ),
                          _buildSourceCard(
                            context: context,
                            icon: Icons.mic_none_outlined,
                            title: 'Audio File',
                            description: 'Upload audio to transcribe',
                            onTap: () => _pickFilesForType(
                              allowedExtensions: ['mp3', 'wav', 'm4a', 'flac', 'ogg'],
                              typeLabel: 'Audio',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // Staged Section Header
                      Row(
                        children: [
                          Text(
                            'STAGED FOR PROCESSING (${sources.length})',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontFamily: 'IBM Plex Mono',
                              fontWeight: FontWeight.w600,
                              color: colors.textSecondary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_computeTotalSize(sources)} Total',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Staged list of cards
                      if (sources.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 36),
                          decoration: BoxDecoration(
                            border: Border.all(color: colors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'No sources staged yet.',
                            style: TextStyle(color: colors.textMuted, fontSize: 13),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: sources.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final source = sources[index];
                            IconData itemIcon;
                            switch (source.type) {
                              case SourceType.pdf:
                                itemIcon = Icons.picture_as_pdf_outlined;
                                break;
                              case SourceType.image:
                                itemIcon = Icons.image_outlined;
                                break;
                              case SourceType.audio:
                                itemIcon = Icons.mic_none_outlined;
                                break;
                              case SourceType.youtube:
                                itemIcon = Icons.play_circle_outline_rounded;
                                break;
                              case SourceType.website:
                                itemIcon = Icons.link_rounded;
                                break;
                              case SourceType.text:
                                itemIcon = Icons.notes_outlined;
                                break;
                              case SourceType.email:
                                itemIcon = Icons.email_outlined;
                                break;
                            }

                            final isFailed = source.status == SourceStatus.failed;
                            final isProcessing = source.status == SourceStatus.processing;

                            return Container(
                              decoration: BoxDecoration(
                                color: isFailed
                                    ? (isDark ? const Color(0xFF3F1E1E) : const Color(0xFFFFECEB))
                                    : (isDark ? const Color(0xFF202020) : Colors.white),
                                border: Border.all(
                                  color: isFailed ? colors.statusFailed.withValues(alpha: 0.5) : colors.border,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Icon(itemIcon, color: isFailed ? colors.statusFailed : colors.primary, size: 18),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          source.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: isFailed ? colors.statusFailed : colors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        if (isProcessing) ...[
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(2),
                                            child: const LinearProgressIndicator(
                                              value: 0.45,
                                              minHeight: 3,
                                              backgroundColor: Color(0xFFEDEDEB),
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                                            ),
                                          ),
                                        ] else if (isFailed) ...[
                                          Text(
                                            'Unable to fetch resource. Check URL and try again.',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: colors.statusFailed,
                                            ),
                                          ),
                                        ] else ...[
                                          Container(
                                            height: 2,
                                            width: 120,
                                            color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFEDEDEB),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  if (isProcessing)
                                    Text(
                                      'Analyzing...',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colors.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    )
                                  else if (isFailed) ...[
                                    Text(
                                      'Failed',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colors.statusFailed,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(Icons.refresh, size: 14, color: colors.statusFailed),
                                      onPressed: () {},
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ] else
                                    Text(
                                      'Pending',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colors.textMuted,
                                      ),
                                    ),
                                  const SizedBox(width: 12),
                                  IconButton(
                                    icon: Icon(Icons.close, size: 14, color: colors.textSecondary),
                                    onPressed: () async {
                                      try {
                                        await ref
                                            .read(sourcesProvider(widget.workspaceId).notifier)
                                            .deleteSource(source.id);
                                      } catch (_) {}
                                    },
                                    constraints: const BoxConstraints(),
                                    padding: EdgeInsets.zero,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 36),

                      // Start Index Generation Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton.icon(
                            onPressed: sources.isEmpty || _isLoading ? null : _startProcessingPipeline,
                            icon: const Icon(Icons.arrow_forward, size: 14),
                            label: const Text('Start Index Generation'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
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

    if (tutorialState.isActive && tutorialState.currentStep == TutorialStep.addSources) {
      body = TutorialOverlay(
        targetKey: TutorialKeys.pdfSourceCard,
        title: 'Add Knowledge Sources',
        description: 'Upload PDFs, text files, images (OCR), or audio (transcription). All processing happens 100% locally on your machine.',
        onNext: () {
          ref.read(tutorialProvider.notifier).nextStep();
          context.go('/workspace/${widget.workspaceId}');
        },
        onSkip: () => ref.read(tutorialProvider.notifier).skipTutorial(),
        child: body,
      );
    }

    return body;
  }
}

class _WebsiteUrlDialog extends ConsumerStatefulWidget {
  final String workspaceId;
  const _WebsiteUrlDialog({required this.workspaceId});

  @override
  ConsumerState<_WebsiteUrlDialog> createState() => _WebsiteUrlDialogState();
}

class _WebsiteUrlDialogState extends ConsumerState<_WebsiteUrlDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF202020) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Text('Import Website Link', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter webpage URL:', style: TextStyle(fontSize: 13, color: colors.textSecondary)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _controller,
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'https://example.com/tutorial',
                hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.border), borderRadius: BorderRadius.circular(4)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.primary), borderRadius: BorderRadius.circular(4)),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return 'URL is required';
                if (!val.startsWith('http://') && !val.startsWith('https://')) {
                  return 'URL must start with http:// or https://';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : () async {
            if (!_formKey.currentState!.validate()) return;
            setState(() => _submitting = true);
            try {
              await ref.read(sourcesProvider(widget.workspaceId).notifier).addWebsiteUrl(_controller.text.trim());
              if (context.mounted) Navigator.of(context).pop();
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to add website: $e'), backgroundColor: colors.statusFailed),
                );
              }
            } finally {
              if (mounted) setState(() => _submitting = false);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          child: _submitting 
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Add', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}

class _YouTubeUrlDialog extends ConsumerStatefulWidget {
  final String workspaceId;
  const _YouTubeUrlDialog({required this.workspaceId});

  @override
  ConsumerState<_YouTubeUrlDialog> createState() => _YouTubeUrlDialogState();
}

class _YouTubeUrlDialogState extends ConsumerState<_YouTubeUrlDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF202020) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Text('Import YouTube Video', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter YouTube video URL:', style: TextStyle(fontSize: 13, color: colors.textSecondary)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _controller,
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'https://www.youtube.com/watch?v=...',
                hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.border), borderRadius: BorderRadius.circular(4)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.primary), borderRadius: BorderRadius.circular(4)),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return 'URL is required';
                final hasMatch = RegExp(
                  r'(https?://)?(www\.)?(youtube|youtu|youtube-nocookie)\.(com|be)/(watch\?v=|embed/|v/|.+\?v=)?([^&=%\?]{11})'
                ).hasMatch(val.trim());
                if (!hasMatch) return 'Invalid YouTube video URL';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : () async {
            if (!_formKey.currentState!.validate()) return;
            setState(() => _submitting = true);
            try {
              await ref.read(sourcesProvider(widget.workspaceId).notifier).addYouTubeUrl(_controller.text.trim());
              if (context.mounted) Navigator.of(context).pop();
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to add video: $e'), backgroundColor: colors.statusFailed),
                );
              }
            } finally {
              if (mounted) setState(() => _submitting = false);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          child: _submitting 
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Add', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}

class _CopyTextDialog extends ConsumerStatefulWidget {
  final String workspaceId;
  const _CopyTextDialog({required this.workspaceId});

  @override
  ConsumerState<_CopyTextDialog> createState() => _CopyTextDialogState();
}

class _CopyTextDialogState extends ConsumerState<_CopyTextDialog> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF202020) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Text('Paste Copied Text', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary)),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Title:', style: TextStyle(fontSize: 13, color: colors.textSecondary)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _titleController,
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'e.g. Research Notes',
                  hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.border), borderRadius: BorderRadius.circular(4)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.primary), borderRadius: BorderRadius.circular(4)),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Title is required';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              Text('Text Content:', style: TextStyle(fontSize: 13, color: colors.textSecondary)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _contentController,
                maxLines: 8,
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Paste or type text content here...',
                  hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
                  contentPadding: const EdgeInsets.all(12),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.border), borderRadius: BorderRadius.circular(4)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.primary), borderRadius: BorderRadius.circular(4)),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Content is required';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : () async {
            if (!_formKey.currentState!.validate()) return;
            setState(() => _submitting = true);
            try {
              await ref.read(sourcesProvider(widget.workspaceId).notifier).addCopiedText(
                _titleController.text.trim(),
                _contentController.text.trim(),
              );
              if (context.mounted) Navigator.of(context).pop();
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to save text: $e'), backgroundColor: colors.statusFailed),
                );
              }
            } finally {
              if (mounted) setState(() => _submitting = false);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          child: _submitting 
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Add', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}

class _EmailDialog extends ConsumerStatefulWidget {
  final String workspaceId;
  final Future<void> Function({required List<String> allowedExtensions, required String typeLabel}) onPickFile;

  const _EmailDialog({
    required this.workspaceId,
    required this.onPickFile,
  });

  @override
  ConsumerState<_EmailDialog> createState() => _EmailDialogState();
}

class _EmailDialogState extends ConsumerState<_EmailDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  
  final _subjectController = TextEditingController();
  final _senderController = TextEditingController();
  final _recipientController = TextEditingController();
  final _bodyController = TextEditingController();
  
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _subjectController.dispose();
    _senderController.dispose();
    _recipientController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF202020) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Row(
        children: [
          Icon(Icons.email_outlined, color: colors.primary, size: 20),
          const SizedBox(width: 8),
          Text('Add Email Message', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary)),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabController,
              labelColor: colors.primary,
              unselectedLabelColor: colors.textSecondary,
              indicatorColor: colors.primary,
              tabs: const [
                Tab(text: 'Upload EML File'),
                Tab(text: 'Paste Email Text'),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SizedBox(
                height: 340,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Upload EML file
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.upload_file_outlined, size: 48, color: colors.textMuted),
                        const SizedBox(height: 12),
                        Text(
                          'Upload .eml or .msg files from your email client.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: colors.textSecondary),
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            await widget.onPickFile(
                              allowedExtensions: ['eml', 'msg'],
                              typeLabel: 'Email',
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colors.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                          child: const Text('Browse Email Files'),
                        ),
                      ],
                    ),
                    // Tab 2: Paste email content
                    SingleChildScrollView(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Subject:', style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                            const SizedBox(height: 4),
                            TextFormField(
                              controller: _subjectController,
                              style: TextStyle(color: colors.textPrimary, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'e.g. Project Update Q3',
                                hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.border), borderRadius: BorderRadius.circular(4)),
                                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.primary), borderRadius: BorderRadius.circular(4)),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Subject is required';
                                return null;
                              },
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('From:', style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                                      const SizedBox(height: 4),
                                      TextFormField(
                                        controller: _senderController,
                                        style: TextStyle(color: colors.textPrimary, fontSize: 13),
                                        decoration: InputDecoration(
                                          hintText: 'sender@example.com',
                                          hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.border), borderRadius: BorderRadius.circular(4)),
                                          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.primary), borderRadius: BorderRadius.circular(4)),
                                        ),
                                        validator: (val) {
                                          if (val == null || val.trim().isEmpty) return 'Sender is required';
                                          return null;
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('To:', style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                                      const SizedBox(height: 4),
                                      TextFormField(
                                        controller: _recipientController,
                                        style: TextStyle(color: colors.textPrimary, fontSize: 13),
                                        decoration: InputDecoration(
                                          hintText: 'recipient@example.com',
                                          hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.border), borderRadius: BorderRadius.circular(4)),
                                          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.primary), borderRadius: BorderRadius.circular(4)),
                                        ),
                                        validator: (val) {
                                          if (val == null || val.trim().isEmpty) return 'Recipient is required';
                                          return null;
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text('Email Body:', style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                            const SizedBox(height: 4),
                            TextFormField(
                              controller: _bodyController,
                              maxLines: 4,
                              style: TextStyle(color: colors.textPrimary, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Enter email body content here...',
                                hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
                                contentPadding: const EdgeInsets.all(10),
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.border), borderRadius: BorderRadius.circular(4)),
                                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.primary), borderRadius: BorderRadius.circular(4)),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Body is required';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
        ),
        AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) {
            if (_tabController.index == 0) return const SizedBox.shrink();
            return ElevatedButton(
              onPressed: _submitting ? null : () async {
                if (!_formKey.currentState!.validate()) return;
                setState(() => _submitting = true);
                try {
                  await ref.read(sourcesProvider(widget.workspaceId).notifier).addCopiedEmail(
                    _subjectController.text.trim(),
                    _senderController.text.trim(),
                    _recipientController.text.trim(),
                    _bodyController.text.trim(),
                  );
                  if (context.mounted) Navigator.of(context).pop();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to save email: $e'), backgroundColor: colors.statusFailed),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _submitting = false);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: _submitting
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Add Email', style: TextStyle(fontSize: 13)),
            );
          },
        ),
      ],
    );
  }
}
