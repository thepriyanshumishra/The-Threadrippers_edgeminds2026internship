// features/source_upload/providers/source_providers.dart
// Purpose: Riverpod providers and state notifier to manage workspace sources.
// Responsibilities: Handles listing, uploading files, adding YouTube URLs, and deleting sources.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../workspace/providers/workspace_providers.dart';
import '../models/source.dart';
import '../services/source_service.dart';

final sourcesProvider = StateNotifierProvider.family<SourcesNotifier, AsyncValue<List<Source>>, String>((ref, workspaceId) {
  final service = ref.watch(sourceServiceProvider);
  return SourcesNotifier(service, workspaceId, ref);
});

class SourcesNotifier extends StateNotifier<AsyncValue<List<Source>>> {
  final SourceService _service;
  final String _workspaceId;
  final Ref _ref;

  SourcesNotifier(this._service, this._workspaceId, this._ref) : super(const AsyncValue.loading()) {
    loadSources();
  }

  Future<void> loadSources() async {
    try {
      final hasData = state.hasValue;
      if (!hasData) {
        state = const AsyncValue.loading();
      }
      final list = await _service.getSources(_workspaceId);
      state = AsyncValue.data(list);
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
    }
  }

  Future<void> uploadFile(List<int> bytes, String fileName) async {
    try {
      final newSources = await _service.uploadFile(_workspaceId, bytes, fileName);
      state.whenData((currentList) {
        state = AsyncValue.data([...currentList, ...newSources]);
      });
      // Refresh workspaces list to update sources_count on home screen
      _ref.read(workspacesProvider.notifier).loadWorkspaces();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> addYouTubeUrl(String url) async {
    try {
      final newSource = await _service.addYouTubeUrl(_workspaceId, url);
      state.whenData((currentList) {
        state = AsyncValue.data([...currentList, newSource]);
      });
      // Refresh workspaces list to update sources_count on home screen
      _ref.read(workspacesProvider.notifier).loadWorkspaces();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteSource(String sourceId) async {
    try {
      await _service.deleteSource(_workspaceId, sourceId);
      state.whenData((currentList) {
        final updatedList = currentList.where((s) => s.id != sourceId).toList();
        state = AsyncValue.data(updatedList);
      });
      // Refresh workspaces list to update sources_count on home screen
      _ref.read(workspacesProvider.notifier).loadWorkspaces();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> addWebsiteUrl(String url) async {
    try {
      final newSource = await _service.addWebsiteUrl(_workspaceId, url);
      state.whenData((currentList) {
        state = AsyncValue.data([...currentList, newSource]);
      });
      // Refresh workspaces list to update sources_count on home screen
      _ref.read(workspacesProvider.notifier).loadWorkspaces();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> addCopiedText(String title, String content) async {
    try {
      final newSource = await _service.addCopiedText(_workspaceId, title, content);
      state.whenData((currentList) {
        state = AsyncValue.data([...currentList, newSource]);
      });
      // Refresh workspaces list to update sources_count on home screen
      _ref.read(workspacesProvider.notifier).loadWorkspaces();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> addCopiedEmail(String subject, String sender, String recipient, String body) async {
    try {
      final newSource = await _service.addCopiedEmail(_workspaceId, subject, sender, recipient, body);
      state.whenData((currentList) {
        state = AsyncValue.data([...currentList, newSource]);
      });
      // Refresh workspaces list to update sources_count on home screen
      _ref.read(workspacesProvider.notifier).loadWorkspaces();
    } catch (e) {
      rethrow;
    }
  }
}
