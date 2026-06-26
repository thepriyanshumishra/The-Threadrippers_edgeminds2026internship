// features/source_upload/models/source.dart
// Purpose: Defines the Source model and source type enum.
// Responsibilities: Handles JSON serialization and type mapping.

enum SourceType {
  pdf,
  image,
  audio,
  youtube,
  website,
  text,
  email;

  static SourceType fromString(String val) {
    switch (val.toLowerCase()) {
      case 'image':
        return SourceType.image;
      case 'audio':
        return SourceType.audio;
      case 'youtube':
        return SourceType.youtube;
      case 'website':
        return SourceType.website;
      case 'text':
        return SourceType.text;
      case 'email':
        return SourceType.email;
      case 'pdf':
      default:
        return SourceType.pdf;
    }
  }

  String toJson() => name;
}

enum SourceStatus {
  pending,
  processing,
  ready,
  failed;

  static SourceStatus fromString(String val) {
    switch (val.toLowerCase()) {
      case 'processing':
        return SourceStatus.processing;
      case 'ready':
        return SourceStatus.ready;
      case 'failed':
        return SourceStatus.failed;
      case 'pending':
      default:
        return SourceStatus.pending;
    }
  }

  String toJson() => name;
}

class Source {
  final String id;
  final String name;
  final SourceType type;
  final String? path;
  final String? url;
  final DateTime addedAt;
  final int? sizeBytes;
  final SourceStatus status;
  final String? summary;
  final Map<String, dynamic>? stats;

  Source({
    required this.id,
    required this.name,
    required this.type,
    this.path,
    this.url,
    required this.addedAt,
    this.sizeBytes,
    required this.status,
    this.summary,
    this.stats,
  });

  factory Source.fromJson(Map<String, dynamic> json) {
    return Source(
      id: json['id'] as String,
      name: json['name'] as String,
      type: SourceType.fromString(json['type'] as String),
      path: json['path'] as String?,
      url: json['url'] as String?,
      addedAt: DateTime.parse(json['added_at'] as String),
      sizeBytes: json['size_bytes'] as int?,
      status: SourceStatus.fromString(json['status'] as String? ?? 'pending'),
      summary: json['summary'] as String?,
      stats: json['stats'] != null ? Map<String, dynamic>.from(json['stats'] as Map) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.toJson(),
      'path': path,
      'url': url,
      'added_at': addedAt.toIso8601String(),
      'size_bytes': sizeBytes,
      'status': status.toJson(),
      'summary': summary,
      'stats': stats,
    };
  }
}
