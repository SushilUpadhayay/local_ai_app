import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';
import 'package:path_provider/path_provider.dart';

abstract class SttService {
  Future<bool> initialize();
  Future<void> startListening({
    required Function(String text) onResult,
    required Function(String error) onError,
    required Function() onDone,
    String? localeId,
  });
  Future<void> stopListening();
  bool get isListening;
  bool get isAvailable;
}

class WhisperSttService implements SttService {
  final AudioRecorder _recorder = AudioRecorder();
  final String? Function() _activeModelPathProvider;
  final String? Function() _activeModelIdProvider;

  bool _isAvailable = false;
  bool _isListening = false;

  Function(String)? _onResult;
  Function(String)? _onError;
  Function()? _onDone;
  String? _localeId;

  WhisperSttService({
    required String? Function() activeModelPathProvider,
    required String? Function() activeModelIdProvider,
  }) : _activeModelPathProvider = activeModelPathProvider,
       _activeModelIdProvider = activeModelIdProvider;

  @override
  bool get isListening => _isListening;

  @override
  bool get isAvailable => _isAvailable;

  @override
  Future<bool> initialize() async {
    if (_isAvailable) return true;
    try {
      final status = await Permission.microphone.status;
      if (status.isPermanentlyDenied) {
        _isAvailable = false;
        throw Exception(
          'Microphone permission is permanently denied. Please enable it in system settings.',
        );
      }
      if (!status.isGranted) {
        final requestStatus = await Permission.microphone.request();
        if (!requestStatus.isGranted) {
          debugPrint(
            '[WhisperSttService] Microphone permission not granted: $requestStatus',
          );
          _isAvailable = false;
          return false;
        }
      }
      _isAvailable = true;
      return true;
    } catch (e) {
      debugPrint('[WhisperSttService] Exception during initialize: $e');
      _isAvailable = false;
      rethrow;
    }
  }

  @override
  Future<void> startListening({
    required Function(String text) onResult,
    required Function(String error) onError,
    required Function() onDone,
    String? localeId,
  }) async {
    _onResult = onResult;
    _onError = onError;
    _onDone = onDone;
    _localeId = localeId;

    if (!_isAvailable) {
      final ok = await initialize();
      if (!ok) {
        onError('Microphone permission is required for speech recognition.');
        return;
      }
    }

    final modelPath = _activeModelPathProvider();
    if (modelPath == null || modelPath.isEmpty) {
      onError(
        'No speech recognition model active. Please download and activate one.',
      );
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final wavPath = '${tempDir.path}/whisper_record.wav';
      final file = File(wavPath);
      if (await file.exists()) {
        await file.delete();
      }

      // Ensure the directory exists
      await file.parent.create(recursive: true);

      _isListening = true;
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: wavPath,
      );
      debugPrint('[WhisperSttService] Recording started: $wavPath');
    } catch (e) {
      _isListening = false;
      onError('Failed to start recording: $e');
    }
  }

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
            debugPrint('[WhisperSttService]   - $entity.path ($size bytes)');
          }
        }
      }
      debugPrint('[WhisperSttService] =====================================');

      if (!fileExists) {
        final errorMsg =
            'Whisper model file not found at: $modelPath\n'
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

      debugPrint(
        '[WhisperSttService] Initializing Whisper with model: $whisperModel, modelDir: $modelDir',
      );
      final Whisper whisper = Whisper(model: whisperModel, modelDir: modelDir);

      String whisperLang = 'auto';
      if (_localeId != null) {
        if (_localeId!.toLowerCase().startsWith('ne')) {
          whisperLang = 'ne';
        } else if (_localeId!.toLowerCase().startsWith('en')) {
          whisperLang = 'en';
        }
      }

      debugPrint(
        '[WhisperSttService] Transcribing with language: $whisperLang',
      );
      final res = await whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: wavPath,
          language: whisperLang,
          isTranslate: false,
          isNoTimestamps: true,
        ),
      );

      debugPrint('[WhisperSttService] Transcription result: ${res.text}');
      _onResult?.call(res.text.trim());
      _onDone?.call();
    } catch (e) {
      debugPrint('[WhisperSttService] Error transcribing: $e');
      _onError?.call('Transcription failed: $e');
      _onDone?.call();
    }
  }
}
