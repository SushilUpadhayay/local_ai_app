import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/model_item.dart';

class ModelRepository {
  late Directory _modelsDir;
  late File _metadataFile;

  Future<void> init() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    _modelsDir = Directory('${appDocDir.path}/models');
    if (!await _modelsDir.exists()) {
      await _modelsDir.create(recursive: true);
    }
    _metadataFile = File('${_modelsDir.path}/metadata_v2.json');
  }

  String getLocalPathForModel(String id) {
    return '${_modelsDir.path}/$id.gguf';
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
}
