import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';

class UpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;
  final bool hasUpdate;

  UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.hasUpdate,
  });
}

class UpdateService {
  final http.Client _client;

  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  /// Checks if a newer version is available on GitHub.
  Future<UpdateInfo> checkForUpdate() async {
    if (kIsWeb) {
      return UpdateInfo(latestVersion: '', downloadUrl: '', releaseNotes: '', hasUpdate: false);
    }
    try {
      final response = await _client.get(
        Uri.parse('https://api.github.com/repos/thepriyanshumishra/The-Threadrippers_edgeminds2026internship/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return UpdateInfo(latestVersion: '', downloadUrl: '', releaseNotes: '', hasUpdate: false);
      }

      final Map<String, dynamic> data = json.decode(response.body);
      final String latestTag = data['tag_name'] as String? ?? '';
      final String latestVersion = latestTag.replaceAll('v', '').trim();
      final String releaseNotes = data['body'] as String? ?? '';

      // Compare semantic versions
      const currentVersion = AppConstants.appVersion;
      final hasUpdate = _isNewerVersion(currentVersion, latestVersion);

      if (!hasUpdate) {
        return UpdateInfo(latestVersion: latestVersion, downloadUrl: '', releaseNotes: releaseNotes, hasUpdate: false);
      }

      // Find the correct asset download URL for the current platform/arch
      final List<dynamic> assets = data['assets'] as List<dynamic>? ?? [];
      String downloadUrl = '';

      if (Platform.isWindows) {
        // e.g. KivoWorkspace-Windows.exe
        final asset = assets.firstWhere(
          (a) => (a['name'] as String).endsWith('.exe'),
          orElse: () => null,
        );
        if (asset != null) downloadUrl = asset['browser_download_url'] as String;
      } else if (Platform.isMacOS) {
        // e.g. KivoWorkspace-macOS-Silicon.dmg or KivoWorkspace-macOS-Intel.dmg
        final res = await Process.run('uname', ['-m']);
        final arch = res.stdout.toString().trim();
        final isSilicon = arch == 'arm64';
        final pattern = isSilicon ? 'Silicon' : 'Intel';

        final asset = assets.firstWhere(
          (a) => (a['name'] as String).contains(pattern) && (a['name'] as String).endsWith('.dmg'),
          orElse: () => null,
        );
        if (asset != null) downloadUrl = asset['browser_download_url'] as String;
      } else if (Platform.isLinux) {
        // e.g. KivoWorkspace-Linux.AppImage
        final asset = assets.firstWhere(
          (a) => (a['name'] as String).endsWith('.AppImage'),
          orElse: () => null,
        );
        if (asset != null) downloadUrl = asset['browser_download_url'] as String;
      }

      return UpdateInfo(
        latestVersion: latestVersion,
        downloadUrl: downloadUrl,
        releaseNotes: releaseNotes,
        hasUpdate: downloadUrl.isNotEmpty,
      );
    } catch (_) {
      return UpdateInfo(latestVersion: '', downloadUrl: '', releaseNotes: '', hasUpdate: false);
    }
  }

  /// Simple version parser/comparator (handles e.g. 1.0.0 and 1.0.1)
  bool _isNewerVersion(String current, String latest) {
    try {
      final currentParts = current.split('.').map(int.parse).toList();
      final latestParts = latest.split('.').map(int.parse).toList();

      for (var i = 0; i < 3; i++) {
        final c = i < currentParts.length ? currentParts[i] : 0;
        final l = i < latestParts.length ? latestParts[i] : 0;
        if (l > c) return true;
        if (c > l) return false;
      }
    } catch (_) {}
    return false;
  }

  /// Downloads the update file from GitHub to temp directory.
  Stream<double> downloadUpdate(String url, String savePath) async* {
    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      final int totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;

      final File file = File(savePath);
      final IOSink sink = file.openWrite();

      await for (final List<int> chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          yield receivedBytes / totalBytes;
        }
      }
      await sink.close();
    } finally {
      client.close();
    }
  }

  /// Launches the installer and exits Kivo Workspace.
  Future<void> applyUpdate(String filePath) async {
    try {
      if (Platform.isWindows) {
        // Run setup installer
        await Process.start(filePath, [], mode: ProcessStartMode.detached);
        exit(0);
      } else if (Platform.isMacOS) {
        // Open DMG file (mounts it and opens Finder)
        await Process.start('open', [filePath], mode: ProcessStartMode.detached);
      } else if (Platform.isLinux) {
        // Open file using default app opener
        await Process.start('xdg-open', [filePath], mode: ProcessStartMode.detached);
      }
    } catch (_) {}
  }
}
