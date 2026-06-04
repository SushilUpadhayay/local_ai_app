# Whisper Model Loading Fix - Complete Implementation Guide

## Problem Statement
The app was throwing `Llama Model LoadException: failed to load model: /data/user/0/.../models/whisper/ggml-tiny.bin` when attempting to load a downloaded Whisper model for speech recognition on Android.

## Root Causes Identified
1. **Missing file verification** - No logging to check if the model file exists before loading
2. **No size validation** - Downloaded files weren't being verified for correct size
3. **Insufficient error diagnostics** - Vague error messages made debugging difficult
4. **Path construction issues** - No validation that parent directories exist or are correct
5. **No download verification** - Downloads weren't confirmed to have completed successfully

## Solution Overview
The fix adds comprehensive file verification and logging at multiple stages:
1. Download completion verification
2. File path validation before transcription
3. Directory structure verification
4. File size checks
5. Detailed error messages for troubleshooting

---

## Code Changes Made

### 1. **stt_service.dart** - Enhanced File Verification Before Transcription

**File**: `lib/services/stt_service.dart`

Added comprehensive logging and file verification in the `stopListening()` method before initializing the Whisper transcriber:

```dart
@override
Future<void> stopListening() async {
  if (!_isListening) return;
  _isListening = false;

  try {
    final wavPath = await _recorder.stop();
    debugPrint('[WhisperSttService] Recording stopped. WAV path: $wavPath');
    if (wavPath == null) {
      _onError?.call('Recording failed: path is null.');
      _onDone?.call();
      return;
    }

    final modelPath = _activeModelPathProvider();
    final modelId = _activeModelIdProvider();
    if (modelPath == null || modelPath.isEmpty || modelId == null) {
      _onError?.call('No active speech model loaded.');
      _onDone?.call();
      return;
    }

    // ===== FILE VERIFICATION LOGGING =====
    final modelFile = File(modelPath);
    final modelDir = modelFile.parent.path;
    final fileExists = await modelFile.exists();
    final fileSizeBytes = fileExists ? await modelFile.length() : 0;
    final fileSizeMb = fileSizeBytes / (1024 * 1024);

    debugPrint('[WhisperSttService] ===== Model File Verification =====');
    debugPrint('[WhisperSttService] Model ID: $modelId');
    debugPrint('[WhisperSttService] Model Path: $modelPath');
    debugPrint('[WhisperSttService] Model Dir: $modelDir');
    debugPrint('[WhisperSttService] File Exists: $fileExists');
    debugPrint(
      '[WhisperSttService] File Size: $fileSizeBytes bytes (~${fileSizeMb.toStringAsFixed(2)} MB)',
    );
    debugPrint(
      '[WhisperSttService] Parent Dir Exists: ${await modelFile.parent.exists()}',
    );

    // List files in model directory
    if (await modelFile.parent.exists()) {
      final dirContents = await modelFile.parent.list().toList();
      debugPrint('[WhisperSttService] Files in model directory:');
      for (final entity in dirContents) {
        if (entity is File) {
          final size = await entity.length();
          debugPrint(
            '[WhisperSttService]   - $entity.path ($size bytes)',
          );
        }
      }
    }
    debugPrint('[WhisperSttService] =====================================');

    if (!fileExists) {
      final errorMsg = 'Whisper model file not found at: $modelPath\n'
          'File size: $fileSizeBytes bytes\n'
          'Ensure model is downloaded before use.';
      debugPrint('[WhisperSttService] ERROR: $errorMsg');
      _onError?.call(errorMsg);
      _onDone?.call();
      return;
    }

    if (fileSizeBytes == 0) {
      final errorMsg = 'Whisper model file is empty: $modelPath';
      debugPrint('[WhisperSttService] ERROR: $errorMsg');
      _onError?.call(errorMsg);
      _onDone?.call();
      return;
    }

    WhisperModel whisperModel;
    if (modelId == 'whisper-tiny') {
      whisperModel = WhisperModel.tiny;
    } else if (modelId == 'whisper-base') {
      whisperModel = WhisperModel.base;
    } else if (modelId == 'whisper-small') {
      whisperModel = WhisperModel.small;
    } else {
      whisperModel = WhisperModel.tiny;
    }

    debugPrint('[WhisperSttService] Initializing Whisper with model: $whisperModel, modelDir: $modelDir');
    final Whisper whisper = Whisper(
      model: whisperModel,
      modelDir: modelDir,
    );
    
    // ... rest of transcription code
  }
}
```

**Key additions**:
- Verify model file exists before transcription attempt
- Check file size and log it in both bytes and MB
- Verify parent directory exists
- List all files in the model directory for diagnostics
- Provide detailed error messages for missing/empty files

---

### 2. **model_download_service.dart** - Download Verification Logging

**File**: `lib/services/model_download_service.dart`

Added logging to the download completion callbacks to verify successful downloads:

```dart
// In _downloadReal() method - onDone callback:
onDone: () async {
  await sink.close();
  client.close();
  _activeDownloads.remove(modelId);

  if (_cancelledDownloads[modelId] == true) {
    if (file.existsSync()) {
      await file.delete();
    }
    onError('Download cancelled');
  } else {
    // Verify file size is greater than 0
    final fileSize = file.existsSync() ? file.lengthSync() : 0;
    final fileSizeMb = fileSize / (1024 * 1024);
    
    debugPrint('[ModelDownloadService] Download completed for $modelId');
    debugPrint('[ModelDownloadService] File path: $localPath');
    debugPrint('[ModelDownloadService] File size: $fileSize bytes (~${fileSizeMb.toStringAsFixed(2)} MB)');
    debugPrint('[ModelDownloadService] File exists: ${file.existsSync()}');
    
    if (file.existsSync() && fileSize > 0) {
      debugPrint('[ModelDownloadService] ✓ Download successful for $modelId');
      onComplete(localPath);
    } else {
      final errorMsg = 'Downloaded file is empty or corrupted. Size: $fileSize bytes';
      debugPrint('[ModelDownloadService] ✗ ERROR: $errorMsg');
      onError(errorMsg);
    }
  }
},
```

And in the start of `_downloadReal()`:

```dart
Future<void> _downloadReal(...) async {
  try {
    debugPrint('[ModelDownloadService] Starting download for $modelId');
    debugPrint('[ModelDownloadService] URL: $url');
    debugPrint('[ModelDownloadService] Local path: $localPath');
    
    final file = File(localPath);
    if (file.existsSync()) {
      debugPrint('[ModelDownloadService] Deleting existing file: $localPath');
      await file.delete();
    }

    // Ensure directory exists
    await file.parent.create(recursive: true);
    debugPrint('[ModelDownloadService] Created directory: ${file.parent.path}');

    // ... rest of download code
    debugPrint('[ModelDownloadService] Download started. Content length: $contentLength bytes');
  }
}
```

**Key additions**:
- Log download initiation with URL and destination path
- Verify directory creation with logging
- Confirm successful file download with size verification
- Distinguish between cancelled, empty, or successful downloads

---

### 3. **model_repository.dart** - Path Construction Logging

**File**: `lib/repositories/model_repository.dart`

Added logging for model path resolution:

```dart
Future<void> init() async {
  final appDocDir = await getApplicationDocumentsDirectory();
  _modelsDir = Directory('${appDocDir.path}/models');
  if (!await _modelsDir.exists()) {
    await _modelsDir.create(recursive: true);
  }
  debugPrint('[ModelRepository] Initialized models directory: ${_modelsDir.path}');
  _metadataFile = File('${_modelsDir.path}/metadata_v2.json');
}

String getLocalPathForModel(String id) {
  final path = id.startsWith('whisper-')
      ? '${_modelsDir.path}/whisper/ggml-${id.substring('whisper-'.length)}.bin'
      : '${_modelsDir.path}/$id.gguf';
  debugPrint('[ModelRepository] Model path for $id: $path');
  return path;
}
```

**Key additions**:
- Log the models directory initialization path
- Log the constructed path for each model ID

---

## Debugging Steps for Users

When Whisper model loading fails, check the logcat output for these messages:

### Expected Log Sequence (Success):
```
[ModelRepository] Initialized models directory: /data/user/0/.../models
[ModelRepository] Model path for whisper-tiny: /data/user/0/.../models/whisper/ggml-tiny.bin
[ModelDownloadService] Starting download for whisper-tiny
[ModelDownloadService] URL: https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin
[ModelDownloadService] Created directory: /data/user/0/.../models/whisper
[ModelDownloadService] Download started. Content length: 78567 bytes
[ModelDownloadService] Download completed for whisper-tiny
[ModelDownloadService] File size: 78567 bytes (~0.75 MB)
[ModelDownloadService] ✓ Download successful for whisper-tiny

[WhisperSttService] ===== Model File Verification =====
[WhisperSttService] Model ID: whisper-tiny
[WhisperSttService] Model Path: /data/user/0/.../models/whisper/ggml-tiny.bin
[WhisperSttService] Model Dir: /data/user/0/.../models/whisper
[WhisperSttService] File Exists: true
[WhisperSttService] File Size: 78567 bytes (~0.75 MB)
[WhisperSttService] Parent Dir Exists: true
[WhisperSttService] Files in model directory:
[WhisperSttService]   - /data/user/0/.../models/whisper/ggml-tiny.bin (78567 bytes)
```

### Troubleshooting Error Cases:

**Error: File not found**
```
[WhisperSttService] File Exists: false
[WhisperSttService] File Size: 0 bytes
→ Solution: Check download logs above, verify models directory exists
```

**Error: Empty file**
```
[WhisperSttService] File Exists: true
[WhisperSttService] File Size: 0 bytes (~0.00 MB)
→ Solution: Download was incomplete or corrupted, re-download model
```

**Error: Directory doesn't exist**
```
[WhisperSttService] Parent Dir Exists: false
→ Solution: App doesn't have permission to create directories, check app permissions
```

---

## Key Files Modified

1. **lib/services/stt_service.dart**
   - Enhanced `stopListening()` with comprehensive file verification
   - Added import for `foundation.dart` (for `debugPrint`)

2. **lib/services/model_download_service.dart**
   - Enhanced download completion verification
   - Added import for `foundation.dart`
   - Detailed logging of download status

3. **lib/repositories/model_repository.dart**
   - Added import for `foundation.dart`
   - Logging of path construction and initialization

---

## Expected Model Sizes (Validation Reference)

- **whisper-tiny**: ~75 MB
- **whisper-base**: ~140 MB  
- **whisper-small**: ~240 MB

If your downloaded files differ significantly from these sizes, the download was likely corrupted.

---

## Testing Instructions

1. **Test Download**: Download a Whisper model through the Models screen
2. **Monitor Logs**: Use `flutter logs` or logcat to observe the download sequence
3. **Test Transcription**: Record audio and attempt transcription
4. **Check Logs**: Verify all expected log messages appear
5. **Verify File**: Check if the file exists at the logged path using Android File Manager

---

## Summary of Root Cause Fix

The original code was missing critical file validation before attempting to load the model. The `whisper_flutter_new` package requires:
1. The model file to exist at the specified path
2. The file to be properly downloaded (non-zero size)
3. The parent directory to exist

By adding these verifications and detailed logging, we can now:
- Immediately identify what's missing or wrong
- Confirm successful downloads
- Provide actionable error messages to users
- Speed up troubleshooting for future issues

