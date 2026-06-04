import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';
import 'package:path_provider/path_provider.dart';

/// STT (Speech-to-Text) service interface using Whisper
///
/// This implements a PUSH-TO-TALK pattern:
/// - User manually controls when recording starts/stops (not continuous listening)
/// - Audio is transcribed by Whisper
/// - Results are passed back via callbacks
/// - No automatic message sending or LLM invocation
abstract class SttService {
  Future<bool> initialize();

  /// Start recording audio - called when user taps microphone button
  /// User must call [stopListening] to stop recording and trigger transcription
  Future<void> startListening({
    required Function(String text) onResult,
    required Function(String error) onError,
    required Function() onDone,
    String? localeId,
  });

  /// Stop recording and transcribe the audio
  /// This triggers the onResult callback with the transcribed text
  Future<void> stopListening();
  bool get isListening;
  bool get isAvailable;
}

/// Whisper-based implementation of STT
///
/// PUSH-TO-TALK WORKFLOW:
/// 1. startListening() → records audio to /tmp/whisper_record.wav
/// 2. stopListening() → stops recording and sends to Whisper for transcription
/// 3. onResult callback → returns transcribed text (placed in input field)
/// 4. User manually edits text and presses Send button
/// 5. Only after Send does the LLM generate a response
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
    // Store callbacks for later use in stopListening()
    _onResult = onResult;
    _onError = onError;
    _onDone = onDone;
    _localeId = localeId;

    // Ensure microphone permission is granted
    if (!_isAvailable) {
      final ok = await initialize();
      if (!ok) {
        onError('Microphone permission is required for speech recognition.');
        return;
      }
    }

    // Verify Whisper model is available
    final modelPath = _activeModelPathProvider();
    if (modelPath == null || modelPath.isEmpty) {
      onError(
        'No speech recognition model active. Please download and activate one.',
      );
      return;
    }

    try {
      // Prepare WAV file for recording
      final tempDir = await getTemporaryDirectory();
      final wavPath = '${tempDir.path}/whisper_record.wav';
      final file = File(wavPath);
      if (await file.exists()) {
        await file.delete();
      }

      // Ensure the directory exists
      await file.parent.create(recursive: true);

      // Start recording - user controls recording duration by tapping mic again
      _isListening = true;
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: wavPath,
      );
      debugPrint(
        '[WhisperSttService] PUSH-TO-TALK: Recording started at $wavPath',
      );
    } catch (e) {
      _isListening = false;
      onError('Failed to start recording: $e');
    }
  }

  /// PUSH-TO-TALK: Stop recording and transcribe the audio
  ///
  /// Called when user taps the microphone button a second time (or cancels).
  /// This method:
  /// 1. Stops the audio recording
  /// 2. Validates the Whisper model is available
  /// 3. Sends the audio file to Whisper for transcription
  /// 4. Calls onResult() with the transcribed text
  /// 5. Text is placed in the input field for user to review/edit
  /// 6. User must manually press Send button to trigger LLM
  ///
  /// NO automatic message sending or LLM invocation happens here.
  @override
  Future<void> stopListening() async {
    if (!_isListening) return;
    _isListening = false;

    try {
      final wavPath = await _recorder.stop();
      debugPrint(
        '[WhisperSttService] PUSH-TO-TALK: Recording stopped. WAV path: $wavPath',
      );
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

      // Validate Whisper model file
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

      // Convert model ID to Whisper enum
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

      // Determine language for transcription (Nepali by default)
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

      // Send audio to Whisper for transcription
      final res = await whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: wavPath,
          language: whisperLang,
          isTranslate: false,
          isNoTimestamps: true,
        ),
      );

      // Return transcribed text - it will be placed in input field
      // User can then review, edit, and manually press Send
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
