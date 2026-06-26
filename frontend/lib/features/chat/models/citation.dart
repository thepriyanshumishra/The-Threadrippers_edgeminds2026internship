// features/chat/models/citation.dart
// Purpose: PODO representation of backend citation metadata.
// Responsibilities: Handles JSON deserialization and fields definition.

class Citation {
  final int index;
  final String rawId;
  final String? sourceId;
  final String sourceName;
  final String? snippet;

  Citation({
    required this.index,
    required this.rawId,
    this.sourceId,
    required this.sourceName,
    this.snippet,
  });

  factory Citation.fromJson(Map<String, dynamic> json) {
    return Citation(
      index: json['index'] as int,
      rawId: json['raw_id'] as String,
      sourceId: json['source_id'] as String?,
      sourceName: json['source_name'] as String? ?? 'Source Document',
      snippet: json['snippet'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'raw_id': rawId,
      'source_id': sourceId,
      'source_name': sourceName,
      'snippet': snippet,
    };
  }
}
