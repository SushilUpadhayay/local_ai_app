import 'dart:async';
import 'package:flutter/material.dart';
import 'model_item.dart';
import 'conversation.dart';
import '../services/model_manager.dart';
import '../services/model_download_service.dart';
import '../services/local_llm_service.dart';
import '../services/compatibility_service.dart';
import '../services/context_window_manager.dart';
import '../repositories/conversation_repository.dart';
import '../services/stt_service.dart';
import '../services/tts_service.dart';

enum AppScreen { chat, history, models }

enum VoiceState { idle, listening, processing, speaking, error }

/// The lifecycle state of the local LLM engine.
enum ModelLoadState {
  unloaded, // No model is in memory
  loading, // Model is being initialized / warmed up
  loaded, // Model is ready to accept prompts
  failed, // Model loading failed
}

class AppState extends ChangeNotifier {
  // Navigation
  AppScreen _activeScreen = AppScreen.chat;
  AppScreen get activeScreen => _activeScreen;

  VoiceState _voiceState = VoiceState.idle;
  VoiceState get voiceState => _voiceState;

  // Voice services
  late SttService _sttService;
  TtsService _ttsService = DeviceTtsService();

  // Sentence Queue TTS fields
  final List<String> _sentenceQueue = [];
  String _sentenceBuffer = '';
  bool _isSentenceTtsSpeaking = false;

  @visibleForTesting
  set sttService(SttService service) {
    _sttService = service;
  }

  @visibleForTesting
  set ttsService(TtsService service) {
    _ttsService = service;
    _ttsService.setHandlers(
      onStart: () {
        _voiceState = VoiceState.speaking;
        notifyListeners();
      },
      onComplete: () {
        _isSentenceTtsSpeaking = false;
        if (_sentenceQueue.isNotEmpty) {
          _speakNextSentenceSegment();
        } else {
          if (!_isStreaming) {
            _voiceState = VoiceState.idle;
            _currentlySpeakingMessage = null;
            notifyListeners();
          }
        }
      },
      onError: (err) {
        debugPrint('[Sentence Queue TTS] onError handler: $err');
        _isSentenceTtsSpeaking = false;
        if (_sentenceQueue.isNotEmpty) {
          _speakNextSentenceSegment();
        } else {
          if (!_isStreaming) {
            _voiceState = VoiceState.error;
            _voiceErrorMessage = err;
            _currentlySpeakingMessage = null;
            notifyListeners();
          }
        }
      },
    );
  }

  String _voiceErrorMessage = '';
  String get voiceErrorMessage => _voiceErrorMessage;

  String _downloadErrorMessage = '';
  String get downloadErrorMessage => _downloadErrorMessage;

  void clearDownloadError() {
    _downloadErrorMessage = '';
    notifyListeners();
  }

  Message? _currentlySpeakingMessage;
  Message? get currentlySpeakingMessage => _currentlySpeakingMessage;

  // Services
  final ModelManager modelManager = ModelManager();
  final ModelDownloadService downloadService = ModelDownloadService();
  final LocalLlmService _llmService = LocalLlmService();
  final CompatibilityService _compatibilityService = CompatibilityService();
  final ContextWindowManager _contextWindowManager = ContextWindowManager();
  final ConversationRepository _conversationRepository =
      ConversationRepository();

  // Startup loading state
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  // Device diagnostics (auto-detected)
  /// Total RAM in GB (detected via MethodChannel on Android, fallback 8GB).
  int _deviceRamGb = 8;
  int get deviceRam => _deviceRamGb;

  /// Free storage in GB (detected via MethodChannel on Android, fallback 50GB).
  double _freeStorageGb = 50.0;
  double get freeStorageGb => _freeStorageGb;

  // Model state machine
  ModelLoadState _modelLoadState = ModelLoadState.unloaded;
  ModelLoadState get modelLoadState => _modelLoadState;

  /// Human-readable status message for the loading overlay / error banner.
  String _modelStatusMessage = '';
  String get modelStatusMessage => _modelStatusMessage;

  // Streaming response
  /// The current token being streamed (accumulated into a full AI response).
  String _streamingToken = '';
  String get streamingToken => _streamingToken;

  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;

  StreamSubscription<String>? _llmStreamSub;

  // Models list (delegated)
  List<ModelItem> get models => modelManager.models;
  ModelItem? get activeModel => modelManager.activeModel;

  // Conversations
  final List<Conversation> _conversations = [];
  List<Conversation> get conversations => _conversations;

  Conversation? _activeConversation;
  Conversation? get activeConversation => _activeConversation;

  String _historySearchQuery = '';
  String get historySearchQuery => _historySearchQuery;

  // Legacy typing flag (retained for backward compat); true when streaming.
  bool get isAiTyping => _isStreaming;

  // Voice timers
  Timer? _voiceTimer;

  AppState() {
    _sttService = WhisperSttService(
      activeModelPathProvider: () => modelManager.activeWhisperModel?.localPath,
      activeModelIdProvider: () => modelManager.activeWhisperModelId,
    );
    _initData();
    _initVoiceServices();
  }

  Future<void> _initVoiceServices() async {
    try {
      await _sttService.initialize();
      await _ttsService.initialize();
      _ttsService.setHandlers(
        onStart: () {
          _voiceState = VoiceState.speaking;
          notifyListeners();
        },
        onComplete: () {
          _isSentenceTtsSpeaking = false;
          if (_sentenceQueue.isNotEmpty) {
            _speakNextSentenceSegment();
          } else {
            if (!_isStreaming) {
              _voiceState = VoiceState.idle;
              _currentlySpeakingMessage = null;
              notifyListeners();
            }
          }
        },
        onError: (err) {
          debugPrint('[Sentence Queue TTS] onError handler: $err');
          _isSentenceTtsSpeaking = false;
          if (_sentenceQueue.isNotEmpty) {
            _speakNextSentenceSegment();
          } else {
            if (!_isStreaming) {
              _voiceState = VoiceState.error;
              _voiceErrorMessage = err;
              _currentlySpeakingMessage = null;
              notifyListeners();
            }
          }
        },
      );
    } catch (e) {
      debugPrint('[AppState] Failed to initialize voice services: $e');
    }
  }

  //  INITIALISATION
  Future<void> _initData() async {
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Initialize model metadata (lazy — GGUF binary not loaded yet).
      await modelManager.init();

      // 2. Detect device hardware.
      await _detectDeviceHardware();

      // 3. Load persisted conversations.
      await _loadPersistedConversations();
    } catch (e) {
      debugPrint('[AppState] Init error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _detectDeviceHardware() async {
    try {
      final ramBytes = await _compatibilityService.getDeviceTotalRam();
      final storageBytes = await _compatibilityService.getDeviceFreeStorage();
      _deviceRamGb = (ramBytes / (1024 * 1024 * 1024)).round();
      _freeStorageGb = storageBytes / (1024 * 1024 * 1024);
      debugPrint(
        '[AppState] Device RAM: ${_deviceRamGb}GB  Free storage: ${_freeStorageGb.toStringAsFixed(1)}GB',
      );
    } catch (e) {
      debugPrint('[AppState] Hardware detection failed: $e');
    }
  }

  Future<void> _loadPersistedConversations() async {
    try {
      await _conversationRepository.init();
      final persisted = await _conversationRepository.loadConversations();
      _conversations
        ..clear()
        ..addAll(persisted);
    } catch (e) {
      debugPrint('[AppState] Failed to load conversations: $e');
    }
  }

  //  NAVIGATION
  void switchScreen(AppScreen screen) {
    _activeScreen = screen;
    notifyListeners();
  }

  //  DEVICE PROFILE  (manual override for UI testing)

  void setDeviceRam(int ram) {
    _deviceRamGb = ram;
    notifyListeners();
  }

  //  MODEL OPERATIONS

  /// Called when the user taps "Set Active" on an installed model.
  /// Performs lazy loading: unloads any old model, then loads the new one.
  Future<void> selectModel(ModelItem model) async {
    if (model.status != 'installed') return;
    if (model.localPath == null) return;

    // ── GUARD: Never pass Whisper/speech models to llama_cpp_dart ────────────
    // Whisper models are GGML .bin files — they are not GGUF and cannot be
    // loaded by LlamaEngine. Routing them here crashes with LlamaModel.load().
    if (model.id.startsWith('whisper-') || model.modelFamily == 'Whisper') {
      debugPrint(
        '[AppState] selectModel() called with a Whisper model (${model.id}). '
        'This would crash llama_cpp_dart. Re-routing to selectWhisperModel().',
      );
      await selectWhisperModel(model);
      return;
    }
    // ─────────────────────────────────────────────────────────────────────────

    // Abort any in-progress generation.
    await _cancelGeneration();

    // Validate compatibility before touching the engine.
    final ramOk = await _compatibilityService.checkRamCompatibility(model);
    if (!ramOk) {
      _setModelFailed(
        'Insufficient RAM: ${model.ram} is required but this device only has ${_deviceRamGb}GB.',
      );
      return;
    }

    // Transition → loading.
    _modelLoadState = ModelLoadState.loading;
    _modelStatusMessage = 'Loading ${model.name}…';
    await modelManager.setActiveModel(model.id);
    notifyListeners();

    try {
      debugPrint(
        '[AppState] Loading LLM model via LocalLlmService: '
        'id=${model.id}  family=${model.modelFamily}  path=${model.localPath}',
      );
      await _llmService.loadModel(
        model.localPath!,
        contextWindow: model.contextWindow,
      );
      _modelLoadState = ModelLoadState.loaded;
      _modelStatusMessage = '${model.name} is ready';
      debugPrint('[AppState] Model loaded: ${model.name}');
    } catch (e) {
      _setModelFailed('Failed to load ${model.name}: $e');
    }

    notifyListeners();
  }

  void _setModelFailed(String reason) {
    _modelLoadState = ModelLoadState.failed;
    _modelStatusMessage = reason;
    debugPrint('[AppState] Model failed: $reason');
  }

  // Download

  void downloadModel(ModelItem model) {
    if (model.status != 'available') return;

    _downloadErrorMessage = '';
    model.status = 'downloading';
    model.downloadProgress = 0.0;
    notifyListeners();

    downloadService.downloadModel(
      modelId: model.id,
      url: model.url ?? '',
      localPath: modelManager.getLocalPathForModel(model.id),
      onProgress: (progress) {
        model.downloadProgress = progress;
        notifyListeners();
      },
      onComplete: (localPath) async {
        model.status = 'installed';
        model.downloadProgress = 1.0;
        model.localPath = localPath;
        await modelManager.saveMetadata();
        notifyListeners();
      },
      onError: (error) async {
        model.status = 'available';
        model.downloadProgress = 0.0;
        _downloadErrorMessage = error.toString().replaceFirst('Exception: ', '');
        await modelManager.saveMetadata();
        notifyListeners();
      },
    );
  }

  void cancelDownload(ModelItem model) {
    if (model.status != 'downloading') return;
    downloadService.cancelDownload(model.id);
  }

  Future<void> deleteModel(ModelItem model) async {
    // Unload engine if this is the active model.
    if (activeModel?.id == model.id) {
      await _cancelGeneration();
      await _llmService.unloadModel();
      _modelLoadState = ModelLoadState.unloaded;
      _modelStatusMessage = '';
    }
    await modelManager.deleteModel(model.id);
    notifyListeners();
  }

  // Cancel loading if user switches away

  /// Unload the current model without selecting a new one.
  Future<void> unloadActiveModel() async {
    await _cancelGeneration();
    await _llmService.unloadModel();
    await modelManager.setActiveModel(null);
    _modelLoadState = ModelLoadState.unloaded;
    _modelStatusMessage = '';
    notifyListeners();
  }
  //  CONVERSATION MANAGEMENT

  void selectConversation(Conversation conv) {
    _activeConversation = conv;
    _activeScreen = AppScreen.chat;
    notifyListeners();
  }

  void startNewConversation() {
    _activeConversation = null;
    notifyListeners();
  }

  void searchHistory(String query) {
    _historySearchQuery = query;
    notifyListeners();
  }

  List<Conversation> getFilteredConversations() {
    if (_historySearchQuery.isEmpty) return _conversations;
    return _conversations.where((c) {
      return c.title.toLowerCase().contains(
            _historySearchQuery.toLowerCase(),
          ) ||
          c.preview.toLowerCase().contains(_historySearchQuery.toLowerCase());
    }).toList();
  }

  //  SEND MESSAGE  (streaming via LocalLlmService)

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    if (_isStreaming) return; // Block concurrent requests.

    final userMsg = Message(
      sender: 'user',
      text: text,
      timestamp: DateTime.now(),
    );

    // Upsert conversation
    if (_activeConversation == null) {
      final newConv = Conversation(
        id: 'conv-${DateTime.now().millisecondsSinceEpoch}',
        title: text.length > 25 ? '${text.substring(0, 22)}…' : text,
        preview: text,
        timeLabel: 'Just now',
        messages: [userMsg],
      );
      _conversations.insert(0, newConv);
      _activeConversation = newConv;
    } else {
      _activeConversation!.messages.add(userMsg);
      _bumpConversationPreview(_activeConversation!.id, text);
    }

    _isStreaming = true;
    _streamingToken = '';
    notifyListeners();

    // Guard: no model selected
    final model = activeModel;
    if (model == null) {
      _finishStreamingWithMessage(
        "*(No Active Model Selected)*\n\nTo start chatting:\n1. Open **Local Models** from the menu.\n2. Download a model that fits your device.\n3. Tap **Set Active** to load it into memory.",
        modelName: 'System',
      );
      return;
    }

    // Guard: model not loaded into engine
    if (_modelLoadState != ModelLoadState.loaded) {
      if (_modelLoadState == ModelLoadState.loading) {
        _finishStreamingWithMessage(
          '*(Model is still loading…)*\n\nPlease wait until **${model.name}** finishes initialising before sending messages.',
          modelName: 'System',
        );
      } else if (_modelLoadState == ModelLoadState.failed) {
        _finishStreamingWithMessage(
          '*(Model Load Failed)*\n\n$_modelStatusMessage\n\nPlease try selecting a different model or re-loading this one.',
          modelName: 'System',
        );
      } else {
        // unloaded — trigger lazy load
        _finishStreamingWithMessage(
          '*(Model Not Loaded)*\n\nThe model file is installed but not yet loaded into memory. Go to **Local Models** and tap **Set Active** to load it.',
          modelName: 'System',
        );
      }
      return;
    }

    // Build context-aware ChatML prompt
    final allMessages = _activeConversation?.messages ?? [];
    final contextMessages = _contextWindowManager.getContextMessages(
      allMessages,
      model.contextWindow,
    );
    final prompt = _contextWindowManager.buildChatMLPrompt(
      contextMessages,
      'You are a helpful, concise AI assistant running entirely offline on this device.',
    );

    // Clear buffer, queue, and speaking state for the new stream
    _sentenceQueue.clear();
    _sentenceBuffer = '';
    _isSentenceTtsSpeaking = false;

    // Stream tokens from LLM engine
    final tokenStream = _llmService.generate(prompt);
    _llmStreamSub = tokenStream.listen(
      (token) {
        _streamingToken += token;
        _processSentenceBuffer(token);
        notifyListeners();
      },
      onError: (err) {
        _finishStreamingWithMessage(
          '*(Inference Error)*\n\n${err.toString()}',
          modelName: model.name,
        );
      },
      onDone: () {
        _flushSentenceBuffer();
        final finalText = _streamingToken.isEmpty
            ? '*(No response generated)*'
            : _streamingToken;
        _finishStreamingWithMessage(finalText, modelName: model.name);
      },
      cancelOnError: true,
    );
  }

  /// Commits the streamed text as a completed AI message and persists.
  void _finishStreamingWithMessage(String text, {required String modelName}) {
    _isStreaming = false;
    _streamingToken = '';
    _llmStreamSub?.cancel();
    _llmStreamSub = null;

    final aiMessage = Message(
      sender: 'ai',
      text: text,
      timestamp: DateTime.now(),
      model: modelName,
    );

    if (_activeConversation != null) {
      _activeConversation!.messages.add(aiMessage);
      _bumpConversationPreview(
        _activeConversation!.id,
        text.length > 50 ? '${text.substring(0, 47)}…' : text,
      );
      // Persist asynchronously.
      _persistConversations();
    }

    notifyListeners();
  }

  Future<void> _cancelGeneration() async {
    _llmStreamSub?.cancel();
    _llmStreamSub = null;
    _llmService.cancelGeneration();
    await stopSpeaking();
    if (_isStreaming) {
      _isStreaming = false;
      _streamingToken = '';
      notifyListeners();
    }
  }

  void _processSentenceBuffer(String newTokens) {
    _sentenceBuffer += newTokens;
    final regExp = RegExp(r'[.?!।\n]');
    while (true) {
      final match = regExp.firstMatch(_sentenceBuffer);
      if (match == null) break;
      final end = match.end;
      final sentence = _sentenceBuffer.substring(0, end).trim();
      _sentenceBuffer = _sentenceBuffer.substring(end);
      if (sentence.isNotEmpty) {
        _enqueueSentenceTts(sentence);
      }
    }
  }

  void _flushSentenceBuffer() {
    final leftover = _sentenceBuffer.trim();
    _sentenceBuffer = '';
    if (leftover.isNotEmpty) {
      _enqueueSentenceTts(leftover);
    }
  }

  void _enqueueSentenceTts(String sentence) {
    debugPrint('[Sentence Queue TTS] Enqueuing: "$sentence"');
    _sentenceQueue.add(sentence);
    _speakNextSentenceSegment();
  }

  Future<void> _speakNextSentenceSegment() async {
    if (_isSentenceTtsSpeaking) return;
    if (_sentenceQueue.isEmpty) return;

    _isSentenceTtsSpeaking = true;
    final sentence = _sentenceQueue.removeAt(0);

    try {
      debugPrint('[Sentence Queue TTS] Speaking: "$sentence"');
      _voiceState = VoiceState.speaking;
      notifyListeners();
      await _ttsService.speak(sentence);
    } catch (e) {
      debugPrint('[Sentence Queue TTS] Error speaking: $e');
      _isSentenceTtsSpeaking = false;
      _speakNextSentenceSegment();
    }
  }

  void _bumpConversationPreview(String convId, String preview) {
    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx != -1) {
      final updated = _conversations[idx].copyWith(
        preview: preview,
        timeLabel: 'Just now',
      );
      _conversations[idx] = updated;
      // Keep activeConversation reference consistent.
      if (_activeConversation?.id == convId) {
        _activeConversation = updated;
      }
    }
  }

  Future<void> _persistConversations() async {
    try {
      await _conversationRepository.saveConversations(_conversations);
    } catch (e) {
      debugPrint('[AppState] Failed to persist conversations: $e');
    }
  }

  //  VOICE INTERACTION

  Future<void> selectWhisperModel(ModelItem model) async {
    if (model.status != 'installed') return;
    if (model.localPath == null) return;
    await modelManager.setActiveWhisperModel(model.id);
    notifyListeners();
  }

  Future<void> unloadActiveWhisperModel() async {
    await modelManager.setActiveWhisperModel(null);
    notifyListeners();
  }

  Future<void> startVoiceSession(TextEditingController inputController) async {
    _voiceErrorMessage = '';

    // Check if Whisper model is active
    if (modelManager.activeWhisperModelId == null || modelManager.activeWhisperModel == null) {
      _voiceState = VoiceState.error;
      _voiceErrorMessage = 'No speech recognition model active.\n\nPlease download and activate a Whisper model from the local models screen.';
      notifyListeners();
      return;
    }

    _voiceState = VoiceState.listening;
    notifyListeners();

    try {
      final isSttAvailable = await _sttService.initialize();
      if (!isSttAvailable) {
        _voiceState = VoiceState.error;
        _voiceErrorMessage = 'Speech recognition is not available or permission denied on this device.';
        notifyListeners();
        return;
      }

      // Pass 'ne' as localeId to ensure Nepali transcription, supporting multilingual recognition
      await _sttService.startListening(
        localeId: 'ne',
        onResult: (text) {
          inputController.text = text;
          inputController.selection = TextSelection.fromPosition(
            TextPosition(offset: text.length),
          );
          _voiceState = VoiceState.idle;
          notifyListeners();
        },
        onError: (errorMsg) {
          _voiceState = VoiceState.error;
          _voiceErrorMessage = errorMsg;
          notifyListeners();
        },
        onDone: () {
          if (_voiceState != VoiceState.error && _voiceState != VoiceState.processing) {
            _voiceState = VoiceState.idle;
            notifyListeners();
          }
        },
      );
    } catch (e) {
      _voiceState = VoiceState.error;
      _voiceErrorMessage = 'Failed to start speech recognition: $e';
      notifyListeners();
    }
  }

  Future<void> cancelVoiceSession() async {
    if (_voiceState == VoiceState.listening) {
      _voiceState = VoiceState.processing;
      notifyListeners();
      await _sttService.stopListening();
    } else {
      _voiceState = VoiceState.idle;
      _voiceErrorMessage = '';
      notifyListeners();
    }
  }

  Future<void> speakMessage(Message msg) async {
    if (_currentlySpeakingMessage == msg) {
      await stopSpeaking();
      return;
    }

    // Stop any existing speech first
    await stopSpeaking();

    _currentlySpeakingMessage = msg;
    _voiceState = VoiceState.speaking;
    _voiceErrorMessage = '';
    notifyListeners();

    _sentenceQueue.clear();
    _sentenceBuffer = '';
    _isSentenceTtsSpeaking = false;

    _processSentenceBuffer(msg.text);
    _flushSentenceBuffer();
  }

  Future<void> stopSpeaking() async {
    _sentenceQueue.clear();
    _sentenceBuffer = '';
    _isSentenceTtsSpeaking = false;
    await _ttsService.stop();
    _voiceState = VoiceState.idle;
    _currentlySpeakingMessage = null;
    notifyListeners();
  }

  void clearVoiceError() {
    _voiceState = VoiceState.idle;
    _voiceErrorMessage = '';
    notifyListeners();
  }

  //  DISPOSE
  @override
  void dispose() {
    _voiceTimer?.cancel();
    _llmStreamSub?.cancel();
    _llmService.unloadModel();
    _sttService.stopListening();
    _ttsService.stop();
    super.dispose();
  }
}

