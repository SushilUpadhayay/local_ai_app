import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/model_item.dart';
import '../repositories/model_repository.dart';
import '../services/model_catalog_service.dart';
import '../services/diagnostic_logger.dart';

class ModelManager {
  final ModelRepository _repository = ModelRepository();
  final ModelCatalogService _catalogService = ModelCatalogService();

  List<ModelItem> _models = [];
  List<ModelItem> get models => _models;

  String? _activeModelId;
  String? get activeModelId => _activeModelId;

  String? _activeWhisperModelId;
  String? get activeWhisperModelId => _activeWhisperModelId;

  ModelItem? get activeModel {
    if (_activeModelId == null) return null;
    try {
      return _models.firstWhere((m) => m.id == _activeModelId && m.status == 'installed');
    } catch (_) {
      return null;
    }
  }

  ModelItem? get activeWhisperModel {
    if (_activeWhisperModelId == null) return null;
    try {
      return _models.firstWhere((m) => m.id == _activeWhisperModelId && m.status == 'installed');
    } catch (_) {
      return null;
    }
  }

  // Initialize directory paths and load metadata
  Future<void> init() async {
    await _repository.init();
    await loadMetadata();
  }

  // Get local path where a model file should be stored
  String getLocalPathForModel(String id) {
    return _repository.getLocalPathForModel(id);
  }

  Future<void> loadMetadata() async {
    DiagnosticLogger.logStart(5, 'ModelRepository loads installed model metadata');
    final List<ModelItem>? loadedModels;
    try {
      loadedModels = await _repository.loadModels();
      _activeModelId = await _repository.loadActiveModelId();
      _activeWhisperModelId = await _repository.loadActiveWhisperModelId();
      DiagnosticLogger.logSuccess(5, 'ModelRepository loads installed model metadata');
    } catch (e, stack) {
      DiagnosticLogger.logFailure(5, 'ModelRepository loads installed model metadata', e, stack);
      rethrow;
    }

    final defaultModels = await _catalogService.getAvailableModels();
    debugPrint(
      '[ModelManager] Catalog loaded: ${defaultModels.length} models.',
    );
    for (final model in defaultModels) {
      debugPrint(
        '[ModelManager] Catalog context: '
        'id=${model.id} contextWindow=${model.contextWindow} '
        'maxOutputTokens=${model.maxOutputTokens}',
      );
    }
    // Build a lookup map from catalog for quick access
    final catalogMap = {for (final m in defaultModels) m.id: m};

    if (loadedModels != null && loadedModels.isNotEmpty) {
      debugPrint(
        '[ModelManager] Cached metadata loaded: ${loadedModels.length} models, '
        'activeModelId=$_activeModelId, '
        'activeWhisperModelId=$_activeWhisperModelId',
      );
      final loadedModelIds = loadedModels.map((m) => m.id).toSet();
      bool dirty = false;

      // 1. Refresh immutable catalog fields for existing cached models.
      //    This ensures fixes (e.g. contextWindow changes) take effect without
      //    requiring users to wipe their cache.
      final refreshedModels = loadedModels.map((cached) {
        final catalog = catalogMap[cached.id];
        if (catalog == null) {
          debugPrint(
            '[ModelManager] Context source: id=${cached.id} '
            'custom metadata contextWindow=${cached.contextWindow} '
            '(no catalog entry)',
          );
          return cached; // custom/sideloaded model — keep as-is
        }
        final updated = cached.copyWith(
          contextWindow: catalog.contextWindow,
          url: catalog.url,
          ram: catalog.ram,
          size: catalog.size,
          fullName: catalog.fullName,
          category: catalog.category,
          quantization: catalog.quantization,
          modelFamily: catalog.modelFamily,
        );
        // Detect if anything actually changed so we know whether to re-save
        if (updated.contextWindow != cached.contextWindow ||
            updated.url != cached.url ||
            updated.ram != cached.ram) {
          dirty = true;
        }
        debugPrint(
          '[ModelManager] Context source: id=${cached.id} '
          'cached=${cached.contextWindow} catalog=${catalog.contextWindow} '
          'effective=${updated.contextWindow}',
        );
        return updated;
      }).toList();

      // 2. Append any brand-new catalog models not yet in the cache
      for (final catalogModel in defaultModels) {
        if (!loadedModelIds.contains(catalogModel.id)) {
          debugPrint(
            '[ModelManager] Added catalog model to metadata: '
            'id=${catalogModel.id} contextWindow=${catalogModel.contextWindow}',
          );
          refreshedModels.add(catalogModel);
          dirty = true;
        }
      }

      _models = refreshedModels;
      await _verifyAndHealFiles();

      if (dirty) {
        await saveMetadata();
      }
    } else {
      _activeModelId = null;
      _activeWhisperModelId = null;
      _models = defaultModels;
      debugPrint(
        '[ModelManager] No cached metadata found; using catalog context windows.',
      );
      await saveMetadata();
    }
  }

  // Save metadata to repository
  Future<void> saveMetadata() async {
    await _repository.saveModels(_models);
    await _repository.saveActiveModelId(_activeModelId);
    await _repository.saveActiveWhisperModelId(_activeWhisperModelId);
  }

  // Default models list from ModelCatalogService
  Future<void> _loadDefaultRegistry() async {
    _activeModelId = null;
    _activeWhisperModelId = null;
    _models = await _catalogService.getAvailableModels();
    await saveMetadata();
  }

  // Verifies that installed models physically exist on the file system.
  // Performs dynamic self-healing if a user manually deleted files, or if file download was interrupted.
  Future<void> _verifyAndHealFiles() async {
    bool dirty = false;
    for (int i = 0; i < _models.length; i++) {
      final model = _models[i];
      final expectedPath = getLocalPathForModel(model.id);
      final fileExists = await File(expectedPath).exists();

      if (model.status == 'installed') {
        if (!fileExists) {
          // File was deleted manually, heal state
          _models[i] = model.copyWith(
            status: 'available',
            localPath: null,
            active: false,
            downloadProgress: 0.0,
          );
          if (_activeModelId == model.id) {
            _activeModelId = null;
          }
          if (_activeWhisperModelId == model.id) {
            _activeWhisperModelId = null;
          }
          dirty = true;
        } else {
          // Keep local path sync
          if (model.localPath != expectedPath) {
            _models[i] = model.copyWith(localPath: expectedPath);
            dirty = true;
          }
        }
      } else {
        // If file exists but marked as available/downloading, mark it as installed
        if (fileExists && model.status != 'downloading') {
          _models[i] = model.copyWith(
            status: 'installed',
            localPath: expectedPath,
            downloadProgress: 1.0,
          );
          dirty = true;
        }
      }
    }

    // Ensure active state matches the activeModelId or activeWhisperModelId
    for (int i = 0; i < _models.length; i++) {
      final model = _models[i];
      final isWhisper = model.id.startsWith('whisper-');
      final currentActiveId = isWhisper ? _activeWhisperModelId : _activeModelId;
      final shouldBeActive = model.id == currentActiveId && model.status == 'installed';
      if (model.active != shouldBeActive) {
        _models[i] = model.copyWith(active: shouldBeActive);
        dirty = true;
      }
    }

    if (dirty) {
      await saveMetadata();
    }
  }

  // Switch/Set active model
  Future<void> setActiveModel(String? id) async {
    if (id == null) {
      _activeModelId = null;
      for (int i = 0; i < _models.length; i++) {
        if (!_models[i].id.startsWith('whisper-')) {
          _models[i] = _models[i].copyWith(active: false);
        }
      }
    } else {
      // Verify model is installed
      try {
        _models.firstWhere((m) => m.id == id && m.status == 'installed');
        _activeModelId = id;
        for (int i = 0; i < _models.length; i++) {
          if (!_models[i].id.startsWith('whisper-')) {
            _models[i] = _models[i].copyWith(active: _models[i].id == id);
          }
        }
      } catch (_) {
        // Model not found or not installed, keep current or do nothing
        return;
      }
    }
    await saveMetadata();
  }

  // Switch/Set active whisper model
  Future<void> setActiveWhisperModel(String? id) async {
    if (id == null) {
      _activeWhisperModelId = null;
      for (int i = 0; i < _models.length; i++) {
        if (_models[i].id.startsWith('whisper-')) {
          _models[i] = _models[i].copyWith(active: false);
        }
      }
    } else {
      // Verify model is installed
      try {
        _models.firstWhere((m) => m.id == id && m.status == 'installed');
        _activeWhisperModelId = id;
        for (int i = 0; i < _models.length; i++) {
          if (_models[i].id.startsWith('whisper-')) {
            _models[i] = _models[i].copyWith(active: _models[i].id == id);
          }
        }
      } catch (_) {
        // Model not found or not installed, keep current or do nothing
        return;
      }
    }
    await saveMetadata();
  }

  // Delete model file and update state
  Future<void> deleteModel(String id) async {
    final expectedPath = getLocalPathForModel(id);
    final file = File(expectedPath);
    if (await file.exists()) {
      await file.delete();
    }

    for (int i = 0; i < _models.length; i++) {
      if (_models[i].id == id) {
        _models[i] = _models[i].copyWith(
          status: 'available',
          localPath: null,
          active: false,
          downloadProgress: 0.0,
        );
      }
    }

    if (_activeModelId == id) {
      _activeModelId = null;
    }
    if (_activeWhisperModelId == id) {
      _activeWhisperModelId = null;
    }

    await saveMetadata();
  }

  // Helper to determine recommendation based on device RAM (in GB)
  String getRecommendationStatus(ModelItem model, int deviceRamGb) {
    if (model.id == 'qwen-0.5b') {
      return 'recommended';
    } else if (model.id == 'qwen-1.5b') {
      if (deviceRamGb >= 6) return 'recommended';
      return 'slow';
    } else if (model.id == 'gemma-2b' || model.id == 'gemma-4-e4b' || model.id == 'qwen-3b') {
      if (deviceRamGb >= 8) return 'recommended';
      if (deviceRamGb >= 6) return 'slow';
      return 'not_recommended';
    } else if (model.id == 'qwen-7b') {
      if (deviceRamGb >= 8) return 'slow';
      return 'not_recommended';
    }
    return 'recommended';
  }
}
