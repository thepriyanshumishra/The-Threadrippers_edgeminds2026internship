// features/processing/models/processing_status.dart
// Purpose: Model for the backend workspace processing status response.
// Responsibilities: Handles JSON deserialization of processing jobs.

class ProcessingStatus {
  final String status;
  final String? currentStep;
  final double progress;
  final List<String> steps;
  final List<String> completedSteps;

  final String? errorType;
  final List<String>? missingPackages;
  final List<String>? failedSources;

  ProcessingStatus({
    required this.status,
    this.currentStep,
    required this.progress,
    required this.steps,
    required this.completedSteps,
    this.errorType,
    this.missingPackages,
    this.failedSources,
  });

  factory ProcessingStatus.fromJson(Map<String, dynamic> json) {
    return ProcessingStatus(
      status: json['status'] as String,
      currentStep: json['current_step'] as String?,
      progress: (json['progress'] as num).toDouble(),
      steps: List<String>.from(json['steps'] as List? ?? []),
      completedSteps: List<String>.from(json['completed_steps'] as List? ?? []),
      errorType: json['error_type'] as String?,
      missingPackages: json['missing_packages'] != null
          ? List<String>.from(json['missing_packages'] as List)
          : null,
      failedSources: json['failed_sources'] != null
          ? List<String>.from(json['failed_sources'] as List)
          : null,
    );
  }

  bool get isProcessing => status == 'processing';
  bool get isReady => status == 'ready';
  bool get isCancelled => status == 'cancelled';
  bool get isFailed => status == 'failed';
}
