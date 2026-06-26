// features/processing/models/system_diagnostics.dart
// Purpose: Model for the backend system diagnostics status response.
// Responsibilities: Handles JSON deserialization of diagnostic service states.

class ServiceStatus {
  final String status;
  final String version;
  final Map<String, dynamic> metadata;

  ServiceStatus({
    required this.status,
    required this.version,
    required this.metadata,
  });

  factory ServiceStatus.fromJson(Map<String, dynamic> json) {
    return ServiceStatus(
      status: json['status'] as String? ?? 'Offline',
      version: json['version'] as String? ?? 'N/A',
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
    );
  }

  bool get isOnline => status == 'Online' || status == 'Ready' || status == 'Connected';
  bool get isWarning => status == 'Warning';
  bool get isOffline => status == 'Offline' || status == 'Error';
}

class SystemDiagnostics {
  final ServiceStatus tesseract;
  final ServiceStatus ffmpeg;
  final ServiceStatus ollama;
  final ServiceStatus database;
  final ServiceStatus storage;

  SystemDiagnostics({
    required this.tesseract,
    required this.ffmpeg,
    required this.ollama,
    required this.database,
    required this.storage,
  });

  factory SystemDiagnostics.fromJson(Map<String, dynamic> json) {
    return SystemDiagnostics(
      tesseract: ServiceStatus.fromJson(Map<String, dynamic>.from(json['tesseract'] ?? {})),
      ffmpeg: ServiceStatus.fromJson(Map<String, dynamic>.from(json['ffmpeg'] ?? {})),
      ollama: ServiceStatus.fromJson(Map<String, dynamic>.from(json['ollama'] ?? {})),
      database: ServiceStatus.fromJson(Map<String, dynamic>.from(json['database'] ?? {})),
      storage: ServiceStatus.fromJson(Map<String, dynamic>.from(json['storage'] ?? {})),
    );
  }
}
