// features/chat/widgets/sources_used_bar.dart
// Purpose: NotebookLM-style "Sources Used" section shown at the bottom of each AI message.
// Responsibilities: Deduplicates citations by source, shows file-type icon, page numbers,
// timestamps, and a rich hover tooltip with snippet + metadata.

import 'package:flutter/material.dart';
import '../models/citation.dart';
import '../../../core/theme/app_colors.dart';

/// Groups one or more [Citation] objects that share the same source.
class _GroupedCitation {
  final String sourceKey; // sourceId if available, else sourceName
  final String sourceName;
  final List<int> pages;
  final List<double> startTimes;
  final String? timestampUrl;
  final String? snippet;
  final double? score;
  // raw_id prefix to guess type
  final String rawId;

  _GroupedCitation({
    required this.sourceKey,
    required this.sourceName,
    required this.pages,
    required this.startTimes,
    this.timestampUrl,
    this.snippet,
    this.score,
    required this.rawId,
  });
}

/// Determines file-type icon from raw_id or source name heuristics.
IconData _sourceIcon(String rawId, String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) { return Icons.picture_as_pdf_rounded; }
  if (lower.endsWith('.mp3') ||
      lower.endsWith('.wav') ||
      lower.endsWith('.m4a') ||
      lower.endsWith('.ogg')) { return Icons.graphic_eq_rounded; }
  if (lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp')) { return Icons.image_rounded; }
  if (lower.contains('youtube') || lower.contains('youtu.be')) {
    return Icons.play_circle_outline_rounded;
  }
  if (lower.startsWith('http') || lower.contains('www.')) {
    return Icons.language_rounded;
  }
  if (lower.endsWith('.txt') || lower.endsWith('.md')) {
    return Icons.article_outlined;
  }
  // Guess from raw_id suffix
  if (rawId.contains('yt_') || rawId.contains('youtube')) {
    return Icons.play_circle_outline_rounded;
  }
  return Icons.description_outlined;
}

/// Color tint for the source-type icon.
Color _sourceColor(String rawId, String name, Color primary) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) { return const Color(0xFFE53935); } // red for PDF
  if (lower.endsWith('.mp3') ||
      lower.endsWith('.wav') ||
      lower.endsWith('.m4a')) { return const Color(0xFF8E24AA); } // purple for audio
  if (lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png')) { return const Color(0xFF1E88E5); } // blue for image
  if (lower.contains('youtube') ||
      lower.contains('youtu.be') ||
      rawId.contains('yt_')) { return const Color(0xFFE53935); } // YouTube red
  if (lower.startsWith('http') || lower.contains('www.')) {
    return const Color(0xFF00897B); // teal for web
  }
  return primary; // default to accent
}

/// Formats a list of seconds into "0:23, 1:05" style strings.
String _formatTimestamp(double seconds) {
  final mins = (seconds ~/ 60).toString();
  final secs = (seconds % 60).toInt().toString().padLeft(2, '0');
  return '$mins:$secs';
}

/// Groups and deduplicates a flat [Citation] list by source.
List<_GroupedCitation> _groupCitations(List<Citation> citations) {
  final Map<String, _GroupedCitation> map = {};
  for (final cit in citations) {
    final key = cit.sourceId ?? cit.sourceName;
    if (map.containsKey(key)) {
      final existing = map[key]!;
      final pages = [...existing.pages];
      final times = [...existing.startTimes];
      if (cit.pages != null) {
        for (final p in cit.pages!) {
          if (!pages.contains(p)) pages.add(p);
        }
      }
      if (cit.startTimes != null) {
        for (final t in cit.startTimes!) {
          if (!times.contains(t)) times.add(t);
        }
      }
      pages.sort();
      map[key] = _GroupedCitation(
        sourceKey: key,
        sourceName: existing.sourceName,
        pages: pages,
        startTimes: times,
        timestampUrl: existing.timestampUrl ?? cit.timestampUrl,
        snippet: existing.snippet ?? cit.snippet,
        score: existing.score ?? cit.score,
        rawId: existing.rawId,
      );
    } else {
      map[key] = _GroupedCitation(
        sourceKey: key,
        sourceName: cit.sourceName,
        pages: List<int>.from(cit.pages ?? []),
        startTimes: List<double>.from(cit.startTimes ?? []),
        timestampUrl: cit.timestampUrl,
        snippet: cit.snippet,
        score: cit.score,
        rawId: cit.rawId,
      );
    }
  }
  return map.values.toList();
}

/// The main widget — renders the "SOURCES USED" header + chip row.
class SourcesUsedBar extends StatelessWidget {
  final List<Citation> citations;

  const SourcesUsedBar({super.key, required this.citations});

  @override
  Widget build(BuildContext context) {
    if (citations.isEmpty) return const SizedBox.shrink();

    final colors = context.colors;
    final grouped = _groupCitations(citations);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        // ── Header ──────────────────────────────────────────────────
        Row(
          children: [
            Container(
              width: 2.5,
              height: 12,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'SOURCES USED',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${grouped.length}',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        // ── Chips ────────────────────────────────────────────────────
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: grouped
              .map((g) => _SourceChip(group: g))
              .toList(),
        ),
      ],
    );
  }
}

/// A single source chip with hover tooltip.
class _SourceChip extends StatefulWidget {
  final _GroupedCitation group;

  const _SourceChip({required this.group});

  @override
  State<_SourceChip> createState() => _SourceChipState();
}

class _SourceChipState extends State<_SourceChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final g = widget.group;

    final icon = _sourceIcon(g.rawId, g.sourceName);
    final iconColor = _sourceColor(g.rawId, g.sourceName, colors.primary);

    // Build meta string — pages or timestamps
    String meta = '';
    if (g.pages.isNotEmpty) {
      final pStr = g.pages.map((p) => 'p.$p').join(', ');
      meta = '  ·  $pStr';
    } else if (g.startTimes.isNotEmpty) {
      final tStr = g.startTimes.map(_formatTimestamp).join(', ');
      meta = '  ·  $tStr';
    }

    // Trim long name
    String displayName = g.sourceName;
    if (displayName.length > 28) {
      displayName = '${displayName.substring(0, 25)}…';
    }

    final chip = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: _hovered
              ? (isDark
                  ? const Color(0xFF2A2A2A)
                  : const Color(0xFFF0F0EE))
              : (isDark
                  ? const Color(0xFF222222)
                  : const Color(0xFFF7F7F5)),
          border: Border.all(
            color: _hovered
                ? colors.primary.withValues(alpha: 0.45)
                : colors.border,
            width: _hovered ? 1.2 : 1.0,
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: iconColor),
            const SizedBox(width: 5),
            Text(
              displayName,
              style: TextStyle(
                fontSize: 11,
                color: _hovered ? colors.textPrimary : colors.textSecondary,
                fontWeight: _hovered ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (meta.isNotEmpty)
              Text(
                meta,
                style: TextStyle(
                  fontSize: 10.5,
                  color: colors.primary.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );

    return _TooltipPopup(group: g, child: chip);
  }
}

/// Custom tooltip popup shown on hover.
class _TooltipPopup extends StatefulWidget {
  final _GroupedCitation group;
  final Widget child;

  const _TooltipPopup({required this.group, required this.child});

  @override
  State<_TooltipPopup> createState() => _TooltipPopupState();
}

class _TooltipPopupState extends State<_TooltipPopup> {
  OverlayEntry? _entry;
  final _layerLink = LayerLink();

  void _show() {
    _removeEntry();
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(builder: (_) => _buildOverlay());
    overlay.insert(_entry!);
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  Widget _buildOverlay() {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final g = widget.group;

    final icon = _sourceIcon(g.rawId, g.sourceName);
    final iconColor = _sourceColor(g.rawId, g.sourceName, colors.primary);

    return Positioned(
      width: 320,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, -8),
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        child: Material(
          color: Colors.transparent,
          child: MouseRegion(
            onEnter: (_) {},
            onExit: (_) => _removeEntry(),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 320),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1C1C1E).withValues(alpha: 0.97)
                    : Colors.white.withValues(alpha: 0.98),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.09),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Source name row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Icon(icon, size: 13, color: iconColor),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            g.sourceName,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    // Pages / timestamps
                    if (g.pages.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _metaRow(
                        icon: Icons.bookmark_border_rounded,
                        label:
                            'Page${g.pages.length > 1 ? 's' : ''}: ${g.pages.join(', ')}',
                        color: colors,
                      ),
                    ],
                    if (g.startTimes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _metaRow(
                        icon: Icons.access_time_rounded,
                        label:
                            'Timestamp${g.startTimes.length > 1 ? 's' : ''}: ${g.startTimes.map(_formatTimestamp).join(', ')}',
                        color: colors,
                      ),
                    ],
                    // Snippet
                    if (g.snippet != null && g.snippet!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(6),
                          border: Border(
                            left: BorderSide(
                              color: colors.primary.withValues(alpha: 0.4),
                              width: 3,
                            ),
                          ),
                        ),
                        child: Text(
                          g.snippet!,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                            height: 1.5,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    // Relevance score
                    if (g.score != null && g.score! > 0) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            'Relevance',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: colors.textMuted,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: (g.score! / 1.0).clamp(0.0, 1.0),
                                minHeight: 3,
                                backgroundColor:
                                    colors.primary.withValues(alpha: 0.12),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  colors.primary.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${(g.score! * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: colors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaRow(
      {required IconData icon,
      required String label,
      required AppColors color}) {
    return Row(
      children: [
        Icon(icon, size: 11, color: color.primary.withValues(alpha: 0.7)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) => _show(),
        onExit: (_) {
          // Small delay so user can move to the tooltip
          Future.delayed(const Duration(milliseconds: 80), () {
            if (mounted) _removeEntry();
          });
        },
        child: widget.child,
      ),
    );
  }

  @override
  void dispose() {
    _removeEntry();
    super.dispose();
  }
}
