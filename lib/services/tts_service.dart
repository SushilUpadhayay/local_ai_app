import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

abstract class TtsService {
  Future<void> initialize();
  Future<void> speak(String text);
  Future<void> stop();
  bool get isSpeaking;
  void setHandlers({
    VoidCallback? onStart,
    VoidCallback? onComplete,
    Function(String)? onError,
  });
}

class DeviceTtsService implements TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;
  bool _isStopping = false;

  VoidCallback? _onStart;
  VoidCallback? _onComplete;
  Function(String)? _onError;

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  Future<void> initialize() async {
    try {
      _flutterTts.setStartHandler(() {
        _isSpeaking = true;
        _isStopping = false;
        debugPrint('[TtsService] Speech started');
        if (_onStart != null) _onStart!();
      });

      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        _isStopping = false;
        debugPrint('[TtsService] Speech completed');
        if (_onComplete != null) _onComplete!();
      });

      _flutterTts.setCancelHandler(() {
        _isSpeaking = false;
        _isStopping = false;
        debugPrint('[TtsService] Speech cancelled');
        if (_onComplete != null) _onComplete!();
      });

      _flutterTts.setErrorHandler((msg) {
        _isSpeaking = false;
        _isStopping = false;
        debugPrint('[TtsService] Speech error: $msg');
        if (_onError != null) _onError!(msg.toString());
      });
    } catch (e) {
      debugPrint('[TtsService] Init error: $e');
    }
  }

  @override
  void setHandlers({
    VoidCallback? onStart,
    VoidCallback? onComplete,
    Function(String)? onError,
  }) {
    _onStart = onStart;
    _onComplete = onComplete;
    _onError = onError;
  }

  @override
  Future<void> speak(String text) async {
    // Don't start new speech if we're in the process of stopping
    if (_isStopping) {
      debugPrint('[TtsService] Ignoring speak() call - TTS is stopping');
      return;
    }

    _isSpeaking = true;
    _isStopping = false;

    try {
      // Check if Nepali is supported by the device TTS engine
      bool isNepaliAvailable = false;
      try {
        final res = await _flutterTts.isLanguageAvailable("ne-NP");
        if (res != null) {
          isNepaliAvailable = res as bool;
        }
      } catch (e) {
        debugPrint('[TtsService] Error checking language ne-NP: $e');
      }

      if (isNepaliAvailable) {
        await _flutterTts.setLanguage("ne-NP");
        debugPrint('[TtsService] Set language to Nepali');
      } else {
        await _flutterTts.setLanguage("en-US");
        debugPrint('[TtsService] Set language to English');
      }
    } catch (e) {
      debugPrint('[TtsService] Error setting language, using default: $e');
    }

    try {
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(
        0.5,
      ); // Standard speed for natural listening
      debugPrint(
        '[TtsService] Enqueueing speech: "${text.substring(0, text.length > 50 ? 50 : text.length)}..."',
      );
      await _flutterTts.speak(text);
    } catch (e) {
      _isSpeaking = false;
      _isStopping = false;
      debugPrint('[TtsService] Speak error: $e');
      if (_onError != null) {
        _onError!(e.toString());
      }
    }
  }

  @override
  Future<void> stop() async {
    if (_isStopping) {
      debugPrint(
        '[TtsService] Stop already in progress, ignoring duplicate call',
      );
      return;
    }

    _isStopping = true;
    _isSpeaking = false;

    try {
      debugPrint('[TtsService] Calling stop on native TTS engine');
      await _flutterTts.stop();
      _isStopping = false;
      debugPrint('[TtsService] Native TTS stop completed');
    } catch (e) {
      _isStopping = false;
      debugPrint('[TtsService] Stop error: $e');
    }
  }
}
