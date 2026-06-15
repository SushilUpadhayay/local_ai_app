import 'dart:io';
import 'package:flutter/services.dart';
import '../models/model_item.dart';

class CompatibilityService {
  static const _channel = MethodChannel('com.localai.app/system_info');

  // Fetch device total RAM in bytes. Falls back to 8GB on unsupported platforms.
  Future<int> getDeviceTotalRam() async {
    if (!Platform.isAndroid) {
      return 8 * 1024 * 1024 * 1024; // Fallback to 8GB for Desktop/Web testing
    }
    try {
      final int? ram = await _channel.invokeMethod<int>('getTotalRam');
      return ram ?? (8 * 1024 * 1024 * 1024);
    } catch (_) {
      return 8 * 1024 * 1024 * 1024;
    }
  }

  // Fetch device free storage in bytes. Falls back to 50GB on unsupported platforms.
  Future<int> getDeviceFreeStorage() async {
    if (!Platform.isAndroid) {
      return 50 *
          1024 *
          1024 *
          1024; // Fallback to 50GB for Desktop/Web testing
    }
    try {
      final int? storage = await _channel.invokeMethod<int>('getFreeStorage');
      return storage ?? (50 * 1024 * 1024 * 1024);
    } catch (_) {
      return 50 * 1024 * 1024 * 1024;
    }
  }

  // Get required RAM for a model in bytes
  int getRequiredRamBytes(ModelItem model) {
    if (model.id == 'qwen-0.5b') {
      return 4 * 1024 * 1024 * 1024;
    } else if (model.id == 'qwen-1.5b') {
      return 6 * 1024 * 1024 * 1024;
    } else if (model.id == 'gemma-2b' || model.id == 'qwen-3b') {
      return 6 * 1024 * 1024 * 1024; // Lowered to 6GB for 2B/3B models to work on 6GB phones
    } else if (model.id == 'qwen-7b') {
      return 8 * 1024 * 1024 * 1024;
    }
    return 4 * 1024 * 1024 * 1024; // default to 4GB
  }

  // Get approximate model file size in bytes
  int getModelSizeBytes(ModelItem model) {
    if (model.id == 'qwen-0.5b') {
      return 398 * 1024 * 1024;
    } else if (model.id == 'qwen-1.5b') {
      return 1200 * 1024 * 1024; // ~1.2 GB
    } else if (model.id == 'gemma-2b') {
      return 1600 * 1024 * 1024; // ~1.6 GB
    } else if (model.id == 'qwen-3b') {
      return 1900 * 1024 * 1024; // ~1.9 GB
    } else if (model.id == 'qwen-7b') {
      return 4400 * 1024 * 1024; // ~4.4 GB
    }
    return 500 * 1024 * 1024;
  }

  // Verify RAM compatibility using rounded GB to account for OS reservation
  Future<bool> checkRamCompatibility(ModelItem model) async {
    final totalRamBytes = await getDeviceTotalRam();
    final totalRamGb = (totalRamBytes / (1024 * 1024 * 1024)).round();
    final requiredRamGb = (getRequiredRamBytes(model) / (1024 * 1024 * 1024))
        .round();
    return totalRamGb >= requiredRamGb;
  }

  // Verify Storage compatibility (requires a 1.2x buffer of model size for safety)
  Future<bool> checkStorageCompatibility(ModelItem model) async {
    final freeStorage = await getDeviceFreeStorage();
    final modelSize = getModelSizeBytes(model);
    final requiredStorage = (modelSize * 1.2).toInt();
    return freeStorage >= requiredStorage;
  }

  // Verify if platform supports on-device FFI execution
  bool isPlatformSupported() {
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }
}
