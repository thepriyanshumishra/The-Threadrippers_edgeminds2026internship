// test/workspace_test.dart
// Purpose: Unit tests for Workspace model.
// Responsibilities: Verifies JSON serialization and deserialization.

import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_workspace/features/workspace/models/workspace.dart';

void main() {
  group('Workspace Model Tests', () {
    test('JSON deserialization works correctly', () {
      final json = {
        'id': 'test-uuid-1234',
        'name': 'My Test Workspace',
        'created_at': '2026-06-16T17:00:00.000Z',
        'status': 'processing',
        'sources_count': 3,
      };

      final workspace = Workspace.fromJson(json);

      expect(workspace.id, 'test-uuid-1234');
      expect(workspace.name, 'My Test Workspace');
      expect(workspace.createdAt.isUtc, true);
      expect(workspace.createdAt.year, 2026);
      expect(workspace.createdAt.month, 6);
      expect(workspace.createdAt.day, 16);
      expect(workspace.status, WorkspaceStatus.processing);
      expect(workspace.sourcesCount, 3);
    });

    test('JSON serialization works correctly', () {
      final dt = DateTime.utc(2026, 6, 16, 17, 0, 0);
      final workspace = Workspace(
        id: 'test-uuid-5678',
        name: 'Another Workspace',
        createdAt: dt,
        status: WorkspaceStatus.failed,
        sourcesCount: 0,
      );

      final json = workspace.toJson();

      expect(json['id'], 'test-uuid-5678');
      expect(json['name'], 'Another Workspace');
      expect(json['created_at'], '2026-06-16T17:00:00.000Z');
      expect(json['status'], 'failed');
      expect(json['sources_count'], 0);
    });

    test('copyWith works correctly', () {
      final workspace = Workspace(
        id: '1',
        name: 'Original',
        createdAt: DateTime.now(),
        status: WorkspaceStatus.ready,
        sourcesCount: 1,
      );

      final updated = workspace.copyWith(name: 'Updated', status: WorkspaceStatus.processing);

      expect(updated.id, '1');
      expect(updated.name, 'Updated');
      expect(updated.status, WorkspaceStatus.processing);
      expect(updated.sourcesCount, 1);
    });
  });
}
