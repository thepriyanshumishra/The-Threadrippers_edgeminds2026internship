import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../models/source.dart';
import '../services/source_service.dart';

class SourcePreviewDialog extends StatefulWidget {
  final String workspaceId;
  final Source source;

  const SourcePreviewDialog({
    super.key,
    required this.workspaceId,
    required this.source,
  });

  @override
  State<SourcePreviewDialog> createState() => _SourcePreviewDialogState();
}

class _SourcePreviewDialogState extends State<SourcePreviewDialog> {
  final SourceService _service = SourceService();
  bool _isLoading = true;
  String? _errorMessage;
  int _currentPage = 1;
  int _totalPages = 1;
  String? _previewText;


  @override
  void initState() {
    super.initState();
    _loadPreviewData();
  }

  Future<void> _loadPreviewData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _service.getSourcePreview(widget.workspaceId, widget.source.id);
      if (mounted) {
        setState(() {
          _totalPages = (data['page_count'] as int? ?? 1).clamp(1, 9999);
          _previewText = data['preview_text'] as String?;
          _isLoading = false;
        });

      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Container(
        width: 720,
        constraints: const BoxConstraints(maxHeight: 680),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(_getIconForType(widget.source.type), color: colors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.source.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              widget.source.type.name.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colors.primary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            if (widget.source.sizeBytes != null) ...[
                              Text(' • ', style: TextStyle(color: colors.textMuted, fontSize: 11)),
                              Text(
                                _formatBytes(widget.source.sizeBytes!),
                                style: TextStyle(color: colors.textMuted, fontSize: 11),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: colors.textMuted, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Content Body
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
                          const SizedBox(height: 12),
                          Text('Loading file preview...', style: TextStyle(color: colors.textMuted, fontSize: 13)),
                        ],
                      ),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: colors.statusFailed, fontSize: 13),
                            ),
                          ),
                        )
                      : _buildPreviewBody(context),
            ),

            // Footer Controls
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Status: ${widget.source.status.name.toUpperCase()}',
                    style: TextStyle(fontSize: 12, color: colors.textMuted, fontWeight: FontWeight.w500),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.textPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: const Text('Close Preview', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewBody(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (widget.source.type) {
      case SourceType.pdf:
        final pageImageUrl =
            '${AppConstants.backendBaseUrl}/workspaces/${widget.workspaceId}/sources/${widget.source.id}/page/$_currentPage';
        return Column(
          children: [
            // Page pagination header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: isDark ? const Color(0xFF161618) : const Color(0xFFF7F7F5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 20),
                    onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
                  ),
                  Text(
                    'Page $_currentPage of $_totalPages',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textPrimary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 20),
                    onPressed: _currentPage < _totalPages ? () => setState(() => _currentPage++) : null,
                  ),
                ],
              ),
            ),

            // Page Image Stream
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Image.network(
                      pageImageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _previewText ?? 'PDF Page Rendering Available',
                          style: TextStyle(color: colors.textMuted, fontSize: 13),
                        ),
                      ),
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 400,
                          width: 300,
                          color: isDark ? const Color(0xFF252528) : const Color(0xFFEEEEEE),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

      case SourceType.image:
        final imageUrl =
            '${AppConstants.backendBaseUrl}/workspaces/${widget.workspaceId}/sources/${widget.source.id}/download';
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.broken_image_outlined, size: 48, color: colors.textMuted),
            ),
          ),
        );

      case SourceType.text:
      case SourceType.email:
      case SourceType.website:
      case SourceType.youtube:
      case SourceType.audio:
        return SingleChildScrollView(

          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.source.url != null) ...[
                SelectableText(
                  widget.source.url!,
                  style: TextStyle(fontSize: 13, color: colors.primary, decoration: TextDecoration.underline),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TEXT / CONTENT PREVIEW',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colors.textMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  if (_previewText != null)
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      tooltip: 'Copy preview text',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _previewText!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Preview text copied to clipboard')),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141416) : const Color(0xFFF6F6F4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.border),
                ),
                child: SelectableText(
                  _previewText ?? 'No text content available for preview.',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    height: 1.5,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }

  IconData _getIconForType(SourceType type) {
    switch (type) {
      case SourceType.pdf:
        return Icons.picture_as_pdf_outlined;
      case SourceType.image:
        return Icons.image_outlined;
      case SourceType.audio:
        return Icons.mic_none_outlined;
      case SourceType.youtube:
        return Icons.play_circle_outline_rounded;
      case SourceType.website:
        return Icons.link_rounded;
      case SourceType.text:
        return Icons.notes_outlined;
      case SourceType.email:
        return Icons.email_outlined;
    }
  }
}
