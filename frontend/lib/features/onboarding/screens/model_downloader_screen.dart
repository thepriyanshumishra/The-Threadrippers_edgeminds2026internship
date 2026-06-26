// features/onboarding/screens/model_downloader_screen.dart
// Purpose: Model selection, download, and management screen with split-pane layout and cancellation.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme/app_colors.dart';
import '../models/onboarding_state.dart';
import '../providers/onboarding_provider.dart';
import '../services/onboarding_prefs.dart';
import '../../../core/theme/theme_provider.dart';

class ModelDownloaderScreen extends ConsumerStatefulWidget {
  const ModelDownloaderScreen({super.key});

  @override
  ConsumerState<ModelDownloaderScreen> createState() => _ModelDownloaderScreenState();
}

class _ModelDownloaderScreenState extends ConsumerState<ModelDownloaderScreen> {
  String _selectedCategory = 'Installed';
  List<String> _downloadedModels = [];
  bool _isLoading = true;

  // Custom model local state
  final TextEditingController _customModelController = TextEditingController();
  String? _customModelError;
  bool _isValidatingCustomModel = false;
  CuratedModel? _verifiedCustomModel;

  // Active download state
  String? _activeDownloadingModel;
  double _downloadProgress = 0.0;
  String _downloadStatusText = '';
  StreamSubscription? _downloadSub;

  @override
  void initState() {
    super.initState();
    _loadDownloadedModels();
  }

  Future<void> _loadDownloadedModels() async {
    final list = await OnboardingPrefs.getDownloadedModels();
    setState(() {
      _downloadedModels = list;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    _customModelController.dispose();
    super.dispose();
  }

  Future<void> _startDownload(CuratedModel model) async {
    if (_activeDownloadingModel != null) return;

    setState(() {
      _activeDownloadingModel = model.id;
      _downloadProgress = 0.0;
      _downloadStatusText = 'Connecting to Ollama...';
    });

    final service = ref.read(onboardingServiceProvider);
    
    try {
      _downloadSub = service.pullOllamaModel(model.id).listen((progress) {
        setState(() {
          _downloadProgress = progress;
          _downloadStatusText = 'Downloading: ${(progress * 100).toStringAsFixed(0)}%';
        });
      }, onError: (err) {
        _showErrorSnackBar('Download failed: $err');
        _resetActiveDownload();
      }, onDone: () async {
        // Add to downloaded models
        final updated = [..._downloadedModels, model.id];
        await OnboardingPrefs.write({
          'downloadedModels': updated,
          'activeModel': model.id, // Set as active model
        });
        
        // Ensure registered in curated registry if it was custom
        if (!curatedModelRegistry.any((m) => m.id == model.id)) {
          curatedModelRegistry.add(model);
        }
        
        _showSuccessSnackBar('${model.name} downloaded successfully!');
        _resetActiveDownload();
        _loadDownloadedModels();
      });
    } catch (e) {
      _showErrorSnackBar('Failed to trigger pull: $e');
      _resetActiveDownload();
    }
  }

  void _resetActiveDownload() {
    _downloadSub?.cancel();
    _downloadSub = null;
    setState(() {
      _activeDownloadingModel = null;
      _downloadProgress = 0.0;
      _downloadStatusText = '';
    });
  }

  Future<void> _deleteModel(String modelId) async {
    final service = ref.read(onboardingServiceProvider);
    final ollamaUrl = await OnboardingPrefs.getOllamaUrl();

    try {
      await service.deleteOllamaModel(modelId, ollamaUrl: ollamaUrl);
      
      final updated = List<String>.from(_downloadedModels)..remove(modelId);
      await OnboardingPrefs.write({
        'downloadedModels': updated,
      });

      final active = await OnboardingPrefs.getActiveModel();
      if (active == modelId) {
        final newActive = updated.isNotEmpty ? updated.first : 'qwen2.5:1.5b';
        await OnboardingPrefs.write({
          'activeModel': newActive,
        });
        ref.read(activeModelProvider.notifier).state = newActive;
      }
      
      _showSuccessSnackBar('Model $modelId deleted successfully!');
      _loadDownloadedModels();
    } catch (e) {
      _showErrorSnackBar('Failed to delete model: $e');
    }
  }

  void _showDeleteConfirmation(String modelId, String modelName) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        backgroundColor: isDark ? const Color(0xFF202020) : const Color(0xFFFBFBFA),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.border),
        ),
        title: Text(
          'Delete Model?',
          style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete the model "$modelName" ($modelId)? This will remove it from your device and release storage space.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteModel(modelId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.statusFailed,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: context.colors.statusFailed),
    );
  }

  void _showSuccessSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: context.colors.statusReady),
    );
  }

  // --- Custom model helpers ---
  String _extractModelId(String input) {
    final trimmed = input.trim();
    final pullPrefixRegex = RegExp(r'^ollama\s+pull\s+', caseSensitive: false);
    if (pullPrefixRegex.hasMatch(trimmed)) {
      return trimmed.replaceFirst(pullPrefixRegex, '').trim();
    }
    return trimmed;
  }

  Future<String> _resolveDefaultTag(String modelPath) async {
    try {
      final tagsUrl = Uri.parse('https://ollama.com/library/${modelPath.replaceFirst('library/', '')}');
      final res = await http.get(tagsUrl);
      if (res.statusCode == 200) {
        final tagsRegex = RegExp(r'data-tag="([^"]+)"');
        final tags = tagsRegex.allMatches(res.body).map((m) => m.group(1)!).toList();
        if (tags.isNotEmpty) return tags.first;
      }
    } catch (_) {}
    return 'latest';
  }

  Future<Map<String, dynamic>?> _fetchRemoteModelInfo(String id) async {
    try {
      String modelPath = id;
      String tag = 'latest';
      if (id.contains(':')) { final parts = id.split(':'); modelPath = parts[0]; tag = parts[1]; }
      if (!modelPath.contains('/')) modelPath = 'library/$modelPath';

      final manifestUrl = Uri.parse('https://registry.ollama.ai/v2/$modelPath/manifests/$tag');
      var res = await http.get(manifestUrl, headers: {'Accept': 'application/vnd.docker.distribution.manifest.v2+json'});

      if (res.statusCode == 401) {
        final tokenUrl = Uri.parse('https://registry.ollama.ai/v2/token?service=registry.ollama.ai&scope=repository:$modelPath:pull');
        final tokenRes = await http.get(tokenUrl);
        if (tokenRes.statusCode == 200) {
          final token = jsonDecode(tokenRes.body)['token'] as String?;
          if (token != null) {
            res = await http.get(manifestUrl, headers: {'Authorization': 'Bearer $token', 'Accept': 'application/vnd.docker.distribution.manifest.v2+json'});
          }
        }
      }

      if (res.statusCode != 200 && !id.contains(':')) {
        final resolvedTag = await _resolveDefaultTag(modelPath);
        if (resolvedTag != 'latest') {
          tag = resolvedTag;
          final retryUrl = Uri.parse('https://registry.ollama.ai/v2/$modelPath/manifests/$tag');
          res = await http.get(retryUrl, headers: {'Accept': 'application/vnd.docker.distribution.manifest.v2+json'});
          if (res.statusCode == 401) {
            final tokenUrl = Uri.parse('https://registry.ollama.ai/v2/token?service=registry.ollama.ai&scope=repository:$modelPath:pull');
            final tokenRes = await http.get(tokenUrl);
            if (tokenRes.statusCode == 200) {
              final token = jsonDecode(tokenRes.body)['token'] as String?;
              if (token != null) res = await http.get(retryUrl, headers: {'Authorization': 'Bearer $token', 'Accept': 'application/vnd.docker.distribution.manifest.v2+json'});
            }
          }
        }
      }

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        double totalBytes = 0;
        for (final layer in (data['layers'] as List? ?? [])) { totalBytes += (layer['size'] as num? ?? 0); }
        if (totalBytes == 0) totalBytes = (data['config']?['size'] as num? ?? 0).toDouble();
        final sizeGb = totalBytes / (1024 * 1024 * 1024);
        final sizeString = sizeGb > 0 ? '${sizeGb.toStringAsFixed(1)} GB' : 'Unknown';
        final int ramGb = sizeGb < 2.0 ? 4 : sizeGb < 3.5 ? 8 : sizeGb < 6.0 ? 16 : sizeGb < 12.0 ? 24 : 48;
        final finalId = tag == 'latest' ? id : (id.contains(':') ? id : '$id:$tag');
        return {
          'id': finalId, 'name': finalId, 'capability': 'Custom Model',
          'size': sizeString, 'sizeGb': double.parse(sizeGb.toStringAsFixed(2)),
          'ram': '$ramGb GB+', 'ramGb': ramGb,
          'compatibility': sizeGb < 6.0 ? 'All devices' : 'High-spec devices',
          'description': 'Custom model from Ollama library — dynamically fetched.',
        };
      }
    } catch (_) {}
    return null;
  }

  Future<void> _validateAndAddCustomModel(String modelId) async {
    final cleanId = _extractModelId(modelId);
    if (cleanId.isEmpty) return;
    setState(() { _isValidatingCustomModel = true; _customModelError = null; _verifiedCustomModel = null; });

    final isMultimodal = cleanId.toLowerCase().contains(
      RegExp(r'(vision|vl|llava|bakllava|moondream|paligemma|whisper|audio|tts|bark|speech|minicpm-v|vlm|cogvlm|mplug-owl|clip)'));
    if (isMultimodal) {
      setState(() { _isValidatingCustomModel = false; _customModelError = 'Vision and audio models are not supported in Kivo Workspace.'; });
      return;
    }

    final modelInfo = await _fetchRemoteModelInfo(cleanId);
    if (modelInfo == null) {
      setState(() { _isValidatingCustomModel = false; _customModelError = 'Model ID not found. Check the ID at ollama.com/library and try again.'; });
      return;
    }

    final customModel = CuratedModel(
      id: modelInfo['id'] as String, name: modelInfo['name'] as String,
      category: 'Custom', capability: modelInfo['capability'] as String,
      size: modelInfo['size'] as String, sizeGb: modelInfo['sizeGb'] as double,
      ram: modelInfo['ram'] as String, ramGb: modelInfo['ramGb'] as int,
      compatibility: modelInfo['compatibility'] as String, description: modelInfo['description'] as String,
    );

    if (!curatedModelRegistry.any((m) => m.id == customModel.id)) {
      curatedModelRegistry.add(customModel);
    }
    setState(() { _isValidatingCustomModel = false; _verifiedCustomModel = customModel; });
  }

  Widget _buildModelCard(CuratedModel model, AppColors colors) {
    final isDownloaded = _downloadedModels.contains(model.id);
    final isDownloading = _activeDownloadingModel == model.id;

    final Color ramText;
    final Color ramBg;
    if (model.ramGb <= 4) { ramText = colors.statusReady; ramBg = colors.statusReadyBg; }
    else if (model.ramGb <= 8) { ramText = colors.primary; ramBg = colors.primarySubtle; }
    else if (model.ramGb <= 16) { ramText = colors.statusProcessing; ramBg = colors.statusProcessingBg; }
    else { ramText = colors.statusFailed; ramBg = colors.statusFailedBg; }

    return Container(
      height: 115,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.sidebarBackground,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(model.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                    Text(model.capability, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: colors.textMuted), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isDownloaded) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline_rounded, color: colors.statusReady, size: 14),
                    const SizedBox(width: 4),
                    Text('Installed', style: TextStyle(color: colors.statusReady, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: colors.statusFailed, size: 18),
                  tooltip: 'Delete Model',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _showDeleteConfirmation(model.id, model.name),
                ),
              ] else
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed: _activeDownloadingModel != null ? null : () => _startDownload(model),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    child: Text(
                      isDownloading ? 'Pulling...' : 'Download',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          const Spacer(),
          Text(model.description, style: TextStyle(fontSize: 10, color: colors.textSecondary, height: 1.25), maxLines: 2, overflow: TextOverflow.ellipsis),
          const Spacer(),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(4), border: Border.all(color: colors.border)),
                child: Text(model.size, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: colors.textSecondary)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: ramBg, borderRadius: BorderRadius.circular(4)),
                child: Text('RAM: ${model.ram}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: ramText)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCustomModelPanel(AppColors colors) {
    return [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.sidebarBackground,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Import Custom Ollama Model', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'Enter any public Ollama model ID (e.g. llama3:8b) or paste the full pull command (e.g. ollama pull mistral). Kivo will verify compatibility before queuing for download.',
              style: TextStyle(fontSize: 12, color: colors.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _customModelController,
              decoration: InputDecoration(
                labelText: 'Model ID or Pull Command',
                hintText: 'e.g. llama3.2:3b  or  ollama pull gemma3:4b',
                labelStyle: TextStyle(color: colors.textSecondary, fontSize: 13),
                hintStyle: TextStyle(color: colors.textMuted, fontSize: 12),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.primary, width: 2)),
                errorText: _customModelError,
                errorMaxLines: 3,
              ),
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
              onSubmitted: (val) => _validateAndAddCustomModel(val),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton(
                onPressed: _isValidatingCustomModel
                    ? null
                    : () => _validateAndAddCustomModel(_customModelController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isValidatingCustomModel
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                    : const Text('Get Info', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
      if (_verifiedCustomModel != null) ...[  
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.check_circle, color: colors.statusReady, size: 16),
            const SizedBox(width: 6),
            Text('Verified — model details retrieved successfully!', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.statusReady)),
          ],
        ),
        const SizedBox(height: 12),
        _buildModelCard(_verifiedCustomModel!, colors),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // --- RAM-based recommendation logic ---
    int getRamBucket(int ramGb) {
      if (ramGb <= 4) return 4;
      if (ramGb <= 8) return 8;
      if (ramGb <= 16) return 16;
      if (ramGb <= 24) return 24;
      if (ramGb <= 48) return 48;
      return 96;
    }

    List<int> getRecommendedRamBuckets(double systemRamGb) {
      final List<int> ramLevels = [4, 8, 16, 24, 48, 96];
      final lowerLevels = ramLevels.where((level) => level < systemRamGb).toList();
      if (lowerLevels.isEmpty) return [4];
      if (lowerLevels.length == 1) return [lowerLevels.first];
      return [lowerLevels[lowerLevels.length - 2], lowerLevels[lowerLevels.length - 1]];
    }

    // Default to 8 GB — systemSpecs no longer tracked (all dependencies are bundled)
    const systemRamGb = 8.0;
    const hasGPU = false;
    final allowedBuckets = getRecommendedRamBuckets(systemRamGb);

    // Build recommended: 2 models from each of 3 key categories, matching system RAM
    final targetCategories = ['General Chat & Assistant', 'Reasoning & Logic', 'Coding & Technical'];
    final List<CuratedModel> recommendedModels = [];
    final Set<String> recIds = {};
    for (final cat in targetCategories) {
      final catModels = curatedModelRegistry.where((m) => m.category == cat).toList();
      final matching = catModels.where((m) {
        final bucket = getRamBucket(m.ramGb);
        if (!allowedBuckets.contains(bucket)) return false;
        if (m.compatibility.contains('High-end') && !hasGPU) return false;
        return true;
      }).toList();
      int count = 0;
      for (final m in matching) {
        if (count >= 2) break;
        if (!recIds.contains(m.id)) { recommendedModels.add(m); recIds.add(m.id); count++; }
      }
      if (count < 2) {
        for (final m in catModels) {
          if (count >= 2) break;
          if (!recIds.contains(m.id)) { recommendedModels.add(m); recIds.add(m.id); count++; }
        }
      }
    }

    // Build category list with proper order: Installed, Recommended, ..., Custom (last)
    final allCatSet = curatedModelRegistry.map((m) => m.category).toSet().toList();
    allCatSet.remove('Custom');

    final categoryOrder = [
      'Installed', 'Recommended', 'General Chat & Assistant', 'Reasoning & Logic', 'Coding & Technical',
      'Creative & Narrative', 'Educational & Information', 'Summarization', 'High-Capacity Reasoners',
      'Agentic & Tool-Use', 'Roleplay & Storytelling', 'Speed & Low-Resource',
      'Medical & Science', 'Multilingual & Translation', 'Uncensored', 'Custom',
    ];

    final categories = ['Installed', 'Recommended', ...allCatSet, 'Custom'];
    categories.sort((a, b) {
      final ia = categoryOrder.indexOf(a); final ib = categoryOrder.indexOf(b);
      return (ia == -1 ? 99 : ia).compareTo(ib == -1 ? 99 : ib);
    });

    final List<CuratedModel> currentModels;
    if (_selectedCategory == 'Installed') {
      currentModels = _downloadedModels.map((modelId) {
        return curatedModelRegistry.firstWhere(
          (m) => m.id == modelId,
          orElse: () => CuratedModel(
            id: modelId,
            name: modelId,
            category: 'Custom',
            capability: 'Local Model',
            size: 'Unknown size',
            sizeGb: 0,
            ram: 'Unknown',
            ramGb: 0,
            compatibility: 'Compatible',
            description: 'Custom installed model.',
          ),
        );
      }).toList();
    } else if (_selectedCategory == 'Recommended') {
      currentModels = recommendedModels;
    } else {
      currentModels = curatedModelRegistry.where((m) => m.category == _selectedCategory).toList();
    }

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.pop(),
        ),
        title: const Text('Download & Manage Models', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Category Sidebar
                      SizedBox(
                        width: 210,
                        child: ListView(
                          children: categories.map((cat) {
                            final isSel = _selectedCategory == cat;
                            final count = cat == 'Installed'
                                ? _downloadedModels.length
                                : cat == 'Recommended'
                                    ? recommendedModels.where((m) => _downloadedModels.contains(m.id)).length
                                    : curatedModelRegistry
                                        .where((m) => m.category == cat && _downloadedModels.contains(m.id))
                                        .length;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: InkWell(
                                onTap: () => setState(() => _selectedCategory = cat),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                  decoration: BoxDecoration(
                                    color: isSel ? colors.primary.withValues(alpha: 0.1) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 3, height: 14,
                                        decoration: BoxDecoration(
                                          color: isSel ? colors.primary : Colors.transparent,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          cat,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                            color: isSel ? colors.primary : colors.textPrimary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (count > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isSel ? colors.primary.withValues(alpha: 0.2) : colors.border,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            '$count',
                                            style: TextStyle(
                                              color: isSel ? colors.primary : colors.textSecondary,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      // Vertical Divider
                      Container(width: 1, color: colors.border, margin: const EdgeInsets.symmetric(horizontal: 16)),

                      // Right Content Panel
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedCategory == 'Recommended'
                                  ? '⭐ Recommended for Your System'
                                  : _selectedCategory == 'Installed'
                                      ? '📥 Installed Models'
                                      : _selectedCategory,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_selectedCategory == 'Custom')
                                      ..._buildCustomModelPanel(colors)
                                    else if (_selectedCategory == 'Installed' && currentModels.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 60),
                                        child: Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.download_rounded, size: 48, color: colors.textMuted),
                                              const SizedBox(height: 16),
                                              Text(
                                                'No models installed yet',
                                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colors.textPrimary),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Select "Recommended" or other categories in the sidebar\nto browse and download models.',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(fontSize: 12, color: colors.textSecondary),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    else if (currentModels.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 40),
                                        child: Center(child: Text('No models in this category.', style: TextStyle(color: colors.textMuted))),
                                      )
                                    else
                                      GridView.builder(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        itemCount: currentModels.length,
                                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 2,
                                          crossAxisSpacing: 12,
                                          mainAxisSpacing: 12,
                                          mainAxisExtent: 115,
                                        ),
                                        itemBuilder: (context, idx) => _buildModelCard(currentModels[idx], colors),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Download Progress Overlay
                if (_activeDownloadingModel != null)
                  Container(
                    color: Colors.black54,
                    alignment: Alignment.center,
                    child: Card(
                      color: colors.sidebarBackground,
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: colors.border),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Downloading Model Weights',
                              style: TextStyle(fontWeight: FontWeight.bold, color: colors.textPrimary, fontSize: 15),
                            ),
                            const SizedBox(height: 16),
                            LinearProgressIndicator(
                              value: _downloadProgress,
                              backgroundColor: colors.border,
                              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _downloadStatusText,
                              style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 38,
                              child: OutlinedButton(
                                onPressed: () {
                                  _resetActiveDownload();
                                  _showErrorSnackBar('Download cancelled by user.');
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: colors.statusFailed,
                                  side: BorderSide(color: colors.statusFailed.withValues(alpha: 0.5)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                child: const Text('Cancel Download', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
