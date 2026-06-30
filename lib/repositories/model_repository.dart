import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/model_item.dart';

class ModelRepository {
  late Directory _modelsDir;
  late File _metadataFile;

  Future<void> init() async {
    final appDocDir = await getApplicationSupportDirectory();
    _modelsDir = Directory('${appDocDir.path}/models');
    if (!await _modelsDir.exists()) {
      await _modelsDir.create(recursive: true);
    }
    print('[ModelRepository] Initialized models directory: ${_modelsDir.path}');
    _metadataFile = File('${_modelsDir.path}/metadata_v2.json');

    // One-time migration: move any files downloaded into the old
    // app_flutter/models/ path (getApplicationDocumentsDirectory) into the new
    // files/models/ path (getApplicationSupportDirectory) so that the native
    // llama.cpp library can open them.
    await _migrateFromLegacyPath();
  }

  /// Migrates model files from the legacy documents directory to the current
  /// support directory. Safe to call on every launch — exits immediately if the
  /// old directory does not exist.
  Future<void> _migrateFromLegacyPath() async {
    try {
      final oldBase = await getApplicationDocumentsDirectory();
      final oldModelsDir = Directory('${oldBase.path}/models');
      if (!await oldModelsDir.exists()) return;

      print(
        '[ModelRepository] Legacy models dir found at ${oldModelsDir.path}, migrating…',
      );

      await for (final entity in oldModelsDir.list(recursive: true)) {
        if (entity is! File) continue;
        final relativePath = entity.path
            .substring(oldModelsDir.path.length)
            .replaceAll('\\', '/');
        final newFile = File('${_modelsDir.path}$relativePath');

        if (!await newFile.exists()) {
          await newFile.parent.create(recursive: true);
          await entity.copy(newFile.path);
          print('[ModelRepository] Migrated: ${entity.path} → ${newFile.path}');
        }
        await entity.delete();
      }

      // Remove the now-empty legacy directory tree
      try {
        await oldModelsDir.delete(recursive: true);
      } catch (_) {}

      print('[ModelRepository] Migration complete.');
    } catch (e) {
      print('[ModelRepository] Migration warning (non-fatal): $e');
    }
  }

  String getLocalPathForModel(String id) {
    final path = id.startsWith('whisper-')
        ? '${_modelsDir.path}/whisper/ggml-${id.substring('whisper-'.length)}.bin'
        : '${_modelsDir.path}/$id.gguf';
    print('[ModelRepository] Model path for $id: $path');
    return path;
  }

  Future<Map<String, dynamic>?> _readMetadata() async {
    if (!await _metadataFile.exists()) return null;
    try {
      final content = await _metadataFile.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeMetadata(Map<String, dynamic> data) async {
    try {
      await _metadataFile.writeAsString(jsonEncode(data));
    } catch (_) {
      // Ignore write errors in repository layer
    }
  }

  Future<List<ModelItem>?> loadModels() async {
    final data = await _readMetadata();
    if (data == null || data['models'] == null) return null;
    try {
      final List<dynamic> list = data['models'];
      return list.map((m) => ModelItem.fromMap(m)).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveModels(List<ModelItem> models) async {
    final data = await _readMetadata() ?? {};
    data['models'] = models.map((m) => m.toMap()).toList();
    await _writeMetadata(data);
  }

  Future<String?> loadActiveModelId() async {
    final data = await _readMetadata();
    return data?['activeModelId'] as String?;
  }

  Future<void> saveActiveModelId(String? id) async {
    final data = await _readMetadata() ?? {};
    data['activeModelId'] = id;
    await _writeMetadata(data);
  }

  Future<String?> loadActiveWhisperModelId() async {
    final data = await _readMetadata();
    return data?['activeWhisperModelId'] as String?;
  }

  Future<void> saveActiveWhisperModelId(String? id) async {
    final data = await _readMetadata() ?? {};
    data['activeWhisperModelId'] = id;
    await _writeMetadata(data);
  }
}
