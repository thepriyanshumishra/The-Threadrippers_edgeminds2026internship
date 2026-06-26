// test/source_test.dart
// Purpose: Unit tests for Source model.
// Responsibilities: Verifies JSON serialization and deserialization of workspace sources.

import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_workspace/features/source_upload/models/source.dart';

void main() {
  group('Source Model Tests', () {
    test('JSON deserialization for File source works correctly', () {
      final json = {
        'id': 'test-source-1234',
        'name': 'lecture_notes.pdf',
        'type': 'pdf',
        'path': 'storage/workspaces/ws-1/sources/lecture_notes.pdf',
        'url': null,
        'added_at': '2026-06-16T17:00:00.000Z',
        'size_bytes': 102400,
        'status': 'pending',
        'summary': 'This document explains math concepts...',
        'stats': {'pages': 5, 'words': 1200, 'chunks': 3},
      };

      final source = Source.fromJson(json);

      expect(source.id, 'test-source-1234');
      expect(source.name, 'lecture_notes.pdf');
      expect(source.type, SourceType.pdf);
      expect(source.path, 'storage/workspaces/ws-1/sources/lecture_notes.pdf');
      expect(source.url, isNull);
      expect(source.addedAt.isUtc, true);
      expect(source.sizeBytes, 102400);
      expect(source.status, SourceStatus.pending);
      expect(source.summary, 'This document explains math concepts...');
      expect(source.stats?['pages'], 5);
      expect(source.stats?['words'], 1200);
      expect(source.stats?['chunks'], 3);
    });

    test('JSON deserialization for YouTube source works correctly', () {
      final json = {
        'id': 'test-source-5678',
        'name': 'YouTube: dQw4w9WgXcQ',
        'type': 'youtube',
        'path': null,
        'url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'added_at': '2026-06-16T17:10:00.000Z',
        'size_bytes': null,
        'status': 'processing',
      };

      final source = Source.fromJson(json);

      expect(source.id, 'test-source-5678');
      expect(source.name, 'YouTube: dQw4w9WgXcQ');
      expect(source.type, SourceType.youtube);
      expect(source.path, isNull);
      expect(source.url, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(source.addedAt.year, 2026);
      expect(source.sizeBytes, isNull);
      expect(source.status, SourceStatus.processing);
    });

    test('JSON deserialization for Image source works correctly', () {
      final json = {
        'id': 'test-source-image',
        'name': 'screenshot.png',
        'type': 'image',
        'path': 'storage/workspaces/ws-1/sources/screenshot.png',
        'url': null,
        'added_at': '2026-06-16T17:05:00.000Z',
        'size_bytes': 512000,
        'status': 'ready',
        'summary': 'OCR extracted text summary here...',
        'stats': {'width': 1920, 'height': 1080, 'words': 240, 'chunks': 2},
      };

      final source = Source.fromJson(json);

      expect(source.id, 'test-source-image');
      expect(source.name, 'screenshot.png');
      expect(source.type, SourceType.image);
      expect(source.path, 'storage/workspaces/ws-1/sources/screenshot.png');
      expect(source.url, isNull);
      expect(source.sizeBytes, 512000);
      expect(source.status, SourceStatus.ready);
      expect(source.summary, 'OCR extracted text summary here...');
      expect(source.stats?['width'], 1920);
      expect(source.stats?['height'], 1080);
      expect(source.stats?['words'], 240);
      expect(source.stats?['chunks'], 2);
    });

    test('JSON deserialization for Audio source works correctly', () {
      final json = {
        'id': 'test-source-audio',
        'name': 'recording.mp3',
        'type': 'audio',
        'path': 'storage/workspaces/ws-1/sources/recording.mp3',
        'url': null,
        'added_at': '2026-06-16T17:08:00.000Z',
        'size_bytes': 2048576,
        'status': 'ready',
        'summary': 'Whisper transcribed text summary here...',
        'stats': {'duration': 125.4, 'words': 350, 'chunks': 3},
      };

      final source = Source.fromJson(json);

      expect(source.id, 'test-source-audio');
      expect(source.name, 'recording.mp3');
      expect(source.type, SourceType.audio);
      expect(source.path, 'storage/workspaces/ws-1/sources/recording.mp3');
      expect(source.url, isNull);
      expect(source.sizeBytes, 2048576);
      expect(source.status, SourceStatus.ready);
      expect(source.summary, 'Whisper transcribed text summary here...');
      expect(source.stats?['duration'], 125.4);
      expect(source.stats?['words'], 350);
      expect(source.stats?['chunks'], 3);
    });

    test('JSON deserialization for Email source works correctly', () {
      final json = {
        'id': 'test-source-email',
        'name': 'Email: Project Update Q3',
        'type': 'email',
        'path': 'storage/workspaces/ws-1/sources/test-source-email_email.eml',
        'url': null,
        'added_at': '2026-06-16T17:08:00.000Z',
        'size_bytes': 1024,
        'status': 'ready',
        'summary': 'Email from sender@example.com to recipient@example.com...',
        'stats': {'pages': 1, 'words': 150, 'chunks': 1},
      };

      final source = Source.fromJson(json);

      expect(source.id, 'test-source-email');
      expect(source.name, 'Email: Project Update Q3');
      expect(source.type, SourceType.email);
      expect(source.path, 'storage/workspaces/ws-1/sources/test-source-email_email.eml');
      expect(source.url, isNull);
      expect(source.sizeBytes, 1024);
      expect(source.status, SourceStatus.ready);
      expect(source.summary, 'Email from sender@example.com to recipient@example.com...');
      expect(source.stats?['pages'], 1);
      expect(source.stats?['words'], 150);
      expect(source.stats?['chunks'], 1);
    });

    test('JSON deserialization for YouTube source with stats works correctly', () {
      final json = {
        'id': 'test-source-youtube-stats',
        'name': 'Never Gonna Give You Up',
        'type': 'youtube',
        'path': null,
        'url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'added_at': '2026-06-16T17:15:00.000Z',
        'size_bytes': null,
        'status': 'ready',
        'summary': 'Extracted transcription of Rick Astley...',
        'stats': {'duration': 212.0, 'words': 420, 'chunks': 4},
      };

      final source = Source.fromJson(json);

      expect(source.id, 'test-source-youtube-stats');
      expect(source.name, 'Never Gonna Give You Up');
      expect(source.type, SourceType.youtube);
      expect(source.path, isNull);
      expect(source.url, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(source.sizeBytes, isNull);
      expect(source.status, SourceStatus.ready);
      expect(source.summary, 'Extracted transcription of Rick Astley...');
      expect(source.stats?['duration'], 212.0);
      expect(source.stats?['words'], 420);
      expect(source.stats?['chunks'], 4);
    });

    test('JSON serialization works correctly', () {
      final dt = DateTime.utc(2026, 6, 16, 17, 0, 0);
      final source = Source(
        id: 'test-source-9999',
        name: 'intro.mp3',
        type: SourceType.audio,
        path: 'storage/workspaces/ws-1/sources/intro.mp3',
        url: null,
        addedAt: dt,
        sizeBytes: 2048576,
        status: SourceStatus.ready,
      );

      final json = source.toJson();

      expect(json['id'], 'test-source-9999');
      expect(json['name'], 'intro.mp3');
      expect(json['type'], 'audio');
      expect(json['path'], 'storage/workspaces/ws-1/sources/intro.mp3');
      expect(json['url'], isNull);
      expect(json['added_at'], '2026-06-16T17:00:00.000Z');
      expect(json['size_bytes'], 2048576);
      expect(json['status'], 'ready');
    });
  });
}
