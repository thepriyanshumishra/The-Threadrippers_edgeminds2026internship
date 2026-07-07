// features/workspace/models/workspace.dart
// Purpose: Defines the Workspace model and workspace status enum.
// Responsibilities: Handles JSON serialization and status mapping.

enum WorkspaceStatus {
  ready,
  processing,
  failed;

  static WorkspaceStatus fromString(String val) {
    switch (val.toLowerCase()) {
      case 'processing':
        return WorkspaceStatus.processing;
      case 'failed':
        return WorkspaceStatus.failed;
      case 'ready':
      default:
        return WorkspaceStatus.ready;
    }
  }

  String toJson() => name;
}

class Workspace {
  final String id;
  final String name;
  final DateTime createdAt;
  final WorkspaceStatus status;
  final int sourcesCount;
  final String instructions;
  final int sizeBytes;
  final String? errorMessage;

  Workspace({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.status,
    required this.sourcesCount,
    this.instructions = '',
    this.sizeBytes = 0,
    this.errorMessage,
  });

  factory Workspace.fromJson(Map<String, dynamic> json) {
    return Workspace(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      status: WorkspaceStatus.fromString(json['status'] as String? ?? 'ready'),
      sourcesCount: json['sources_count'] as int? ?? 0,
      instructions: json['instructions'] as String? ?? '',
      sizeBytes: json['size_bytes'] as int? ?? 0,
      errorMessage: json['error_message'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt.toIso8601String(),
      'status': status.toJson(),
      'sources_count': sourcesCount,
      'instructions': instructions,
      'size_bytes': sizeBytes,
      'error_message': errorMessage,
    };
  }

  Workspace copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    WorkspaceStatus? status,
    int? sourcesCount,
    String? instructions,
    int? sizeBytes,
    String? errorMessage,
  }) {
    return Workspace(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      sourcesCount: sourcesCount ?? this.sourcesCount,
      instructions: instructions ?? this.instructions,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
