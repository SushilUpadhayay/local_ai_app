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

  // Live Streaming TTS (OPTIONAL: user-initiated real-time speech during generation)
  /// Whether live TTS is actively speaking as text streams in
  bool _isLiveStreamingTts = false;
  bool get isLiveStreamingTts => _isLiveStreamingTts;

  /// Buffered text waiting to be spoken in live streaming mode
  String _liveStreamingTextBuffer = '';

  /// Reference to the message being streamed (for replay button later)
  Message? _currentStreamingMessage;
  Message? get currentStreamingMessage => _currentStreamingMessage;

  /// Whether we're currently speaking a chunk of live stream text
  bool _isLiveStreamingSpeaking = false;

  /// Check if a message is the one currently streaming
  bool isStreamingMessage(Message msg) => _currentStreamingMessage == msg;

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
        _downloadErrorMessage = error.toString().replaceFirst(
          'Exception: ',
          '',
        );
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

  //  SEND MESSAGE  (manual trigger only - NOT automatic)

  /// Send a user message and generate an LLM response
  ///
  /// This method is ONLY called when the user manually presses the Send button.
  /// It is NOT called automatically by the STT (speech-to-text) workflow.
  ///
  /// STT Workflow (PUSH-TO-TALK):
  /// 1. User taps microphone → recording starts
  /// 2. User taps microphone again → Whisper transcribes
  /// 3. Transcription text appears in input field
  /// 4. User manually calls this method by pressing Send button
  /// 5. Only then does the LLM generate a response
  ///
  /// There is NO automatic sending, NO continuous listening, NO automatic processing.
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

    // Reset live streaming state for new message
    _isLiveStreamingTts = false;
    _liveStreamingTextBuffer = '';
    _isLiveStreamingSpeaking = false;
    _currentStreamingMessage = null;

    // Stream tokens from LLM engine
    final tokenStream = _llmService.generate(prompt);
    _llmStreamSub = tokenStream.listen(
      (token) {
        _streamingToken += token;
        _processSentenceBuffer(token);

        // Feed to live TTS if enabled
        _feedLiveStreamingText(token);

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

    // Stop live TTS if it was running (allows replay button to work for full message)
    if (_isLiveStreamingTts) {
      _ttsService.stop();
      _isLiveStreamingTts = false;
      _isLiveStreamingSpeaking = false;
      _liveStreamingTextBuffer = '';
    }

    final aiMessage = Message(
      sender: 'ai',
      text: text,
      timestamp: DateTime.now(),
      model: modelName,
    );

    // Store reference for replay button
    _currentStreamingMessage = aiMessage;

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

  /// PUSH-TO-TALK: Starts recording audio
  ///
  /// Workflow:
  /// 1. User taps microphone button → calls this method
  /// 2. Audio recording starts (state = listening)
  /// 3. User taps microphone button again → calls [cancelVoiceSession]
  /// 4. Recording stops and Whisper transcribes audio (state = processing)
  /// 5. Transcription result populates the input field (NOT automatically sent)
  /// 6. User can edit the text and manually press Send button
  /// 7. Only then does the LLM generate a response
  ///
  /// NO automatic sending of messages occurs.
  Future<void> startVoiceSession(TextEditingController inputController) async {
    _voiceErrorMessage = '';

    // Validate Whisper model is available
    if (modelManager.activeWhisperModelId == null ||
        modelManager.activeWhisperModel == null) {
      _voiceState = VoiceState.error;
      _voiceErrorMessage =
          'No speech recognition model active.\n\nPlease download and activate a Whisper model from the local models screen.';
      notifyListeners();
      return;
    }

    // Update UI: show listening state
    _voiceState = VoiceState.listening;
    notifyListeners();

    try {
      // Initialize microphone permission
      final isSttAvailable = await _sttService.initialize();
      if (!isSttAvailable) {
        _voiceState = VoiceState.error;
        _voiceErrorMessage =
            'Speech recognition is not available or permission denied on this device.';
        notifyListeners();
        return;
      }

      // Start recording with language set to Nepali ('ne')
      // When user taps mic again, stopListening() will be called
      await _sttService.startListening(
        localeId: 'ne',
        // This callback fires when transcription completes
        // Text is placed in input field WITHOUT automatic sending
        onResult: (text) {
          inputController.text = text;
          inputController.selection = TextSelection.fromPosition(
            TextPosition(offset: text.length),
          );
          _voiceState = VoiceState.idle;
          notifyListeners();
          // User must manually press Send button to trigger LLM
        },
        onError: (errorMsg) {
          _voiceState = VoiceState.error;
          _voiceErrorMessage = errorMsg;
          notifyListeners();
        },
        onDone: () {
          if (_voiceState != VoiceState.error &&
              _voiceState != VoiceState.processing) {
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

  /// PUSH-TO-TALK: Stops recording and triggers transcription
  ///
  /// Called when:
  /// 1. User taps the microphone button a second time (during listening)
  /// 2. User taps the cancel button in the voice modal
  ///
  /// This stops audio recording and sends it to Whisper for transcription.
  /// The resulting text is placed in the input field for manual review/editing
  /// before the user presses Send to trigger the LLM.
  Future<void> cancelVoiceSession() async {
    if (_voiceState == VoiceState.listening) {
      // Transition to processing state while Whisper transcribes the audio
      _voiceState = VoiceState.processing;
      notifyListeners();
      // This will trigger the onResult callback which populates the input field
      await _sttService.stopListening();
    } else {
      // User cancelled from modal or error state
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

  // ===== LIVE STREAMING TTS (Optional feature) =====

  /// Start live TTS: speak text chunks as they stream in from the LLM
  /// This is independent from replay/sentence-queue TTS
  /// User must manually tap "🔊 Speak Live" button - never automatic
  void startLiveStreamingTts() {
    // Stop any existing replay speaking
    if (_currentlySpeakingMessage != null) {
      _ttsService.stop();
    }

    _isLiveStreamingTts = true;
    _liveStreamingTextBuffer = '';
    _isLiveStreamingSpeaking = false;
    _currentlySpeakingMessage = null;

    debugPrint('[LiveStreamingTts] Started live streaming TTS');
    notifyListeners();
  }

  /// Stop live TTS (keeps LLM generation running)
  /// Can be restarted by tapping "Speak Live" again
  Future<void> stopLiveStreamingTts() async {
    if (!_isLiveStreamingTts) return;

    _isLiveStreamingTts = false;
    _isLiveStreamingSpeaking = false;
    await _ttsService.stop();
    _liveStreamingTextBuffer = '';

    debugPrint('[LiveStreamingTts] Stopped live streaming TTS');
    notifyListeners();
  }

  /// Queue text for live streaming TTS and speak it
  /// Called for each token that arrives during generation
  void _feedLiveStreamingText(String text) {
    if (!_isLiveStreamingTts) return;

    _liveStreamingTextBuffer += text;

    // Try to speak by sentences/words to keep speech timely
    _speakNextLiveStreamingChunk();
  }

  /// Process buffered text and speak sentence/word chunks
  void _speakNextLiveStreamingChunk() {
    if (!_isLiveStreamingTts || _isLiveStreamingSpeaking) return;
    if (_liveStreamingTextBuffer.isEmpty) return;

    // Split by sentences (. ! ? । \n) or speak word boundary if large buffer
    final sentenceMatch = RegExp(
      r'[.?!।\n]',
    ).firstMatch(_liveStreamingTextBuffer);

    late String textToSpeak;
    late String remaining;

    if (sentenceMatch != null) {
      // Speak up to and including the sentence end
      textToSpeak = _liveStreamingTextBuffer.substring(0, sentenceMatch.end);
      remaining = _liveStreamingTextBuffer
          .substring(sentenceMatch.end)
          .trimLeft();
    } else if (_liveStreamingTextBuffer.length > 50) {
      // Buffer is large but no sentence end - speak at word boundary
      final lastSpace = _liveStreamingTextBuffer.lastIndexOf(' ');
      if (lastSpace > 0 && lastSpace < _liveStreamingTextBuffer.length - 1) {
        textToSpeak = _liveStreamingTextBuffer.substring(0, lastSpace);
        remaining = _liveStreamingTextBuffer.substring(lastSpace).trim();
      } else {
        // No good break point, just accumulate more
        return;
      }
    } else {
      // Buffer is small, wait for more text
      return;
    }

    // Trim and speak
    textToSpeak = textToSpeak.trim();
    if (textToSpeak.isEmpty) {
      _liveStreamingTextBuffer = remaining;
      _speakNextLiveStreamingChunk();
      return;
    }

    _liveStreamingTextBuffer = remaining;
    _isLiveStreamingSpeaking = true;

    debugPrint(
      '[LiveStreamingTts] Speaking chunk: "${textToSpeak.substring(0, textToSpeak.length > 50 ? 50 : textToSpeak.length)}..."',
    );

    _ttsService
        .speak(textToSpeak)
        .then((_) {
          // After this chunk completes, try to speak next
          _isLiveStreamingSpeaking = false;
          _speakNextLiveStreamingChunk();
        })
        .catchError((err) {
          debugPrint('[LiveStreamingTts] Error speaking: $err');
          _isLiveStreamingSpeaking = false;
          _speakNextLiveStreamingChunk();
        });
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
