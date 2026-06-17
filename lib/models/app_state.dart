// ignore_for_file: non_constant_identifier_names
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
import '../services/trek_knowledge_service.dart';
import '../services/tool_registry_service.dart';
import 'dart:convert';

enum AppScreen { chat, history, models }

enum VoiceState { idle, listening, processing, speaking, error }

/// The lifecycle state of the local LLM engine.
enum ModelLoadState {
  unloaded, // No model is in memory
  loading, // Model is being initialized / warmed up
  loaded, // Model is ready to accept prompts
  failed, // Model loading failed
}

enum TtsState { idle, buffering, speaking, stopped, muted }

class _TtsQueueItem {
  final String sentence;
  final int sessionId;
  _TtsQueueItem(this.sentence, this.sessionId);
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

  // === TTS STATE AND CONTROL FLAGS (Single Source of Truth) ===
  TtsState _ttsState = TtsState.idle;
  TtsState get ttsState => _ttsState;

  bool _isTtsEnabled = true;
  bool get isTtsEnabled => _isTtsEnabled;

  bool get isSpeaking =>
      _ttsState == TtsState.speaking || _ttsState == TtsState.buffering;

  int _ttsSessionId = 0;
  int? _activeUtteranceSessionId;
  bool _isVoiceSessionActive = false;

  // Sentence Queue TTS fields
  final List<_TtsQueueItem> _sentenceQueue = [];
  String _sentenceBuffer = '';
  bool _isSentenceTtsSpeaking = false;

  @visibleForTesting
  set sttService(SttService service) {
    _sttService = service;
  }

  @visibleForTesting
  set ttsService(TtsService service) {
    _ttsService = service;
    _registerTtsHandlers();
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
  final TrekKnowledgeService _trekKnowledgeService = TrekKnowledgeService();
  late final ToolRegistryService _toolRegistryService = ToolRegistryService(
    _trekKnowledgeService,
  );
  TrekKnowledgeService get trekKnowledgeService => _trekKnowledgeService;
  ToolRegistryService get toolRegistryService => _toolRegistryService;

  String? _selectedtrek_name;
  String? get selectedTrekName => _selectedtrek_name;
  bool get hasSelectedTrek => _selectedtrek_name != null;

  List<Map<String, dynamic>> get availableTreks {
    final result = _trekKnowledgeService.list_available_treks();
    final data = Map<String, dynamic>.from(result['data'] ?? const {});
    return (data['treks'] as List? ?? const [])
        .whereType<Map>()
        .map((trek) => Map<String, dynamic>.from(trek))
        .toList();
  }

  String get selectedTrekLabel {
    if (_selectedtrek_name == null) return 'None';
    for (final trek in availableTreks) {
      if (trek['trek_name'] == _selectedtrek_name) {
        return trek['name']?.toString() ??
            _readableTrekName(_selectedtrek_name!);
      }
    }
    return _readableTrekName(_selectedtrek_name!);
  }

  // Context retention for trek assistant
  final Map<String, String> _lastSelectedTrekNames = {};

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

  AppState({SttService? sttService, TtsService? ttsService}) {
    _sttService =
        sttService ??
        WhisperSttService(
          activeModelPathProvider: () =>
              modelManager.activeWhisperModel?.localPath,
          activeModelIdProvider: () => modelManager.activeWhisperModelId,
        );
    if (ttsService != null) {
      _ttsService = ttsService;
    }
    _initData();
    _initVoiceServices();
  }

  Future<void> _initVoiceServices() async {
    try {
      await _sttService.initialize();
      await _ttsService.initialize();
      _registerTtsHandlers();
    } catch (e) {
      debugPrint('[AppState] Failed to initialize voice services: $e');
    }
  }

  void _registerTtsHandlers() {
    _ttsService.setHandlers(
      onStart: () {
        if (_activeUtteranceSessionId != _ttsSessionId) {
          debugPrint(
            '[TTS] Ignoring onStart callback for stale session $_activeUtteranceSessionId (current: $_ttsSessionId)',
          );
          return;
        }
        if (_isTtsEnabled) {
          _ttsState = TtsState.speaking;
          _voiceState = VoiceState.speaking;
          notifyListeners();
        }
      },
      onComplete: () {
        _isSentenceTtsSpeaking = false;
        if (_activeUtteranceSessionId != _ttsSessionId) {
          debugPrint(
            '[TTS] Ignoring onComplete callback for stale session $_activeUtteranceSessionId (current: $_ttsSessionId)',
          );
          return;
        }
        _activeUtteranceSessionId =
            null; // Utterance finished — clear reference
        _processQueueAfterUtterance();
      },
      onError: (err) {
        debugPrint('[TTS] Error callback: $err');
        _isSentenceTtsSpeaking = false;
        if (_activeUtteranceSessionId != _ttsSessionId) {
          debugPrint(
            '[TTS] Ignoring onError callback for stale session $_activeUtteranceSessionId (current: $_ttsSessionId)',
          );
          return;
        }
        _activeUtteranceSessionId = null; // Utterance errored — clear reference
        _processQueueAfterUtterance(error: err.toString());
      },
    );
  }

  void _processQueueAfterUtterance({String? error}) {
    if (!_isTtsEnabled) {
      _ttsState = TtsState.idle;
      notifyListeners();
      return;
    }

    // Remove expired items from the front of the queue
    while (_sentenceQueue.isNotEmpty &&
        _sentenceQueue.first.sessionId != _ttsSessionId) {
      _sentenceQueue.removeAt(0);
    }

    if (_sentenceQueue.isNotEmpty) {
      _speakNextSentenceSegment();
    } else {
      _ttsState = TtsState.idle;
      if (!_isStreaming) {
        _voiceState = error != null ? VoiceState.error : VoiceState.idle;
        if (error != null) {
          _voiceErrorMessage = error;
        }
        _currentlySpeakingMessage = null;
      }
      notifyListeners();
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

      // 4. Initialize trek knowledge service.
      await _trekKnowledgeService.initialize();
    } catch (e) {
      debugPrint('[AppState] Init error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  void selectTrek(String trekName) {
    if (!_trekKnowledgeService.isValidTrekName(trekName)) return;
    _selectedtrek_name = trekName;
    notifyListeners();
  }

  void clearSelectedTrek() {
    _selectedtrek_name = null;
    notifyListeners();
  }

  String _readableTrekName(String id) {
    return id
        .split('_')
        .map(
          (word) =>
              word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1),
        )
        .join(' ');
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

    // GUARD: Never pass Whisper/speech models to llama_cpp_dart
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

    final shouldSpeak = _isVoiceSessionActive || _isLiveStreamingTtsEnabled;
    _isVoiceSessionActive = false; // Reset for next message

    _ttsSessionId++; // Invalidate old session and start a new one
    final currentSessionId = _ttsSessionId;

    _isStreaming = true;
    _streamingToken = '';
    if (shouldSpeak) {
      _isTtsEnabled = true;
      _ttsState = TtsState.buffering;
    } else {
      _isTtsEnabled = false;
      _ttsState = TtsState.idle;
    }
    notifyListeners();

    final convId = _activeConversation?.id;
    final lasttrekName = convId != null
        ? _lastSelectedTrekNames[convId]
        : null;

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
        _finishStreamingWithMessage(
          '*(Model Not Loaded)*\n\nThe model file is installed but not yet loaded into memory. Go to **Local Models** and tap **Set Active** to load it.',
          modelName: 'System',
        );
      }
      return;
    }

    final allMessages = _activeConversation?.messages ?? [];
    final contextMessages = _contextWindowManager.getRecentRoleMessages(
      allMessages,
    );
    final agentMessages = <Map<String, dynamic>>[
      ...contextMessages.map(
        (message) => {
          'role': message.sender == 'user' ? 'user' : 'assistant',
          'content': message.text,
        },
      ),
    ];

    _toolRegistryService.beginResponseTrace();
    ReasoningTrace? trace;

    try {
      // ----------------------------------------------------
      // PASS 1: Classification & Routing
      // ----------------------------------------------------
      _streamingToken = 'Thinking locally...\n';
      notifyListeners();

      final treksList = availableTreks
          .map((t) => t['trek_name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      final routerPrompt = _llmService.buildRouterPrompt(
        messages: agentMessages,
        availableTreks: treksList,
      );

      debugPrint('[Agent] PASS 1 Prompt:\n$routerPrompt');

      const routerMaxTokens = 150;
      final routerResponse = await _streamResponse(
        routerPrompt,
        routerMaxTokens,
        currentSessionId,
      );

      debugPrint('[Agent] PASS 1 Raw Output:\n$routerResponse');

      final classification = _parseRouterOutput(routerResponse);
      final type = classification['type'] ?? 'chat';
      debugPrint('[Agent] Router classification: type=$type, details=$classification');

      if (type == 'chat') {
        final chatReply = classification['chat_response']?.trim() ?? '';
        final finalResponse = chatReply.isNotEmpty
            ? chatReply
            : 'Hello! I am ready to help you with your Nepal trekking questions.';

        _sentenceQueue.clear();
        _sentenceBuffer = '';
        _isSentenceTtsSpeaking = false;
        _isLiveStreamingTtsEnabled = false;
        _currentStreamingMessage = null;
        _streamingToken = finalResponse;

        if (_ttsSessionId == currentSessionId && _isTtsEnabled) {
          _processSentenceBuffer(_streamingToken);
          _flushSentenceBuffer();
        }

        _finishStreamingWithMessage(
          _streamingToken,
          modelName: model.name,
          reasoningTrace: null,
        );
        return;
      }

      // ----------------------------------------------------
      // PASS 2: Tool Execution & Grounded Summarization
      // ----------------------------------------------------
      _streamingToken = 'Using offline trek knowledge...\n';
      notifyListeners();

      final toolName = classification['tool_name'] ?? 'get_trek_overview';
      var trekName = classification['trek_name'] ?? _selectedtrek_name ?? lasttrekName ?? 'none';
      if (trekName == 'none' && (_selectedtrek_name != null || lasttrekName != null)) {
        trekName = _selectedtrek_name ?? lasttrekName ?? 'none';
      }

      final category = classification['category'] ?? 'none';
      final question = classification['question'] ?? text;

      final arguments = <String, dynamic>{};
      if (trekName != 'none') {
        arguments['trek_name'] = trekName;
      }
      if (category != 'none') {
        arguments['category'] = category;
      }
      if (question != 'none') {
        arguments['question'] = question;
      }

      final toolCall = ToolCall(
        name: toolName,
        arguments: arguments,
      );

      debugPrint('[Agent] Executing tool: ${toolCall.name} with args: ${toolCall.arguments}');

      final result = _toolRegistryService.execute(toolCall);
      trace = _toolRegistryService.currentTrace;

      final matchedTrek = trace.matchedTrek;
      if (matchedTrek.isNotEmpty && matchedTrek != 'none' && convId != null) {
        _lastSelectedTrekNames[convId] = matchedTrek;
      }

      String contextPayload = '';
      if (result.success) {
        contextPayload = _truncateToolResult(result.payload);
      } else {
        contextPayload = 'No offline data found for category "$category" of trek "$trekName".';
      }

      debugPrint('[Agent] Local tool execution completed. Data: $contextPayload');

      final rephrasePrompt = _llmService.buildRephrasePrompt(
        context: contextPayload,
        messages: agentMessages,
      );

      debugPrint('[Agent] PASS 2 Prompt:\n$rephrasePrompt');

      final maxTokens = model.maxOutputTokens > 0 ? model.maxOutputTokens : 512;
      final finalResponse = await _streamResponse(
        rephrasePrompt,
        maxTokens,
        currentSessionId,
      );

      _sentenceQueue.clear();
      _sentenceBuffer = '';
      _isSentenceTtsSpeaking = false;
      _isLiveStreamingTtsEnabled = false;
      _currentStreamingMessage = null;

      _streamingToken = finalResponse.isEmpty
          ? '*(No response generated)*'
          : finalResponse;

      if (_ttsSessionId == currentSessionId && _isTtsEnabled) {
        _processSentenceBuffer(_streamingToken);
        _flushSentenceBuffer();
      }

      _finishStreamingWithMessage(
        _streamingToken,
        modelName: model.name,
        reasoningTrace: trace,
      );

    } catch (e) {
      _finishStreamingWithMessage(
        '*(Inference Error)*\n\n${e.toString()}',
        modelName: model.name,
        reasoningTrace: trace,
      );
    }
  }

  Map<String, String> _parseRouterOutput(String response) {
    final result = <String, String>{};

    final typeMatch = RegExp(r'Type:\s*(\w+)', caseSensitive: false).firstMatch(response);
    if (typeMatch != null) {
      result['type'] = typeMatch.group(1)!.trim().toLowerCase();
    } else {
      result['type'] = 'chat';
    }

    if (result['type'] == 'chat') {
      final chatResponseIdx = response.indexOf('ChatResponse:');
      if (chatResponseIdx != -1) {
        var chatContent = response.substring(chatResponseIdx + 'ChatResponse:'.length).trim();
        if (chatContent.contains('===')) {
          chatContent = chatContent.split('===')[0].trim();
        }
        result['chat_response'] = chatContent;
      } else {
        result['chat_response'] = response.replaceAll(RegExp(r'Type:\s*chat', caseSensitive: false), '').trim();
      }
    } else {
      final fields = ['TrekName', 'ToolName', 'Category', 'Question'];
      for (final field in fields) {
        final reg = RegExp('$field:\\s*([^\\n]+)', caseSensitive: false);
        final match = reg.firstMatch(response);
        if (match != null) {
          result[field.toLowerCase()] = match.group(1)!.trim();
        }
      }
    }

    return result;
  }

  Future<String> _streamResponse(
    String prompt,
    int maxTokens,
    int currentSessionId,
  ) async {
    final stream = _llmService.generate(prompt, maxTokens: maxTokens);
    final buffer = StringBuffer();
    _streamingToken = '';

    final completer = Completer<void>();

    _llmStreamSub = stream.listen(
      (token) {
        buffer.write(token);
        _streamingToken = buffer.toString();
        notifyListeners();
        if (_isTtsEnabled && _ttsSessionId == currentSessionId) {
          _processSentenceBuffer(token);
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (e) {
        debugPrint('[Agent] Stream error: $e');
        if (!completer.isCompleted) completer.completeError(e);
      },
      cancelOnError: true,
    );

    try {
      await completer.future;
    } catch (e) {
      debugPrint('[Agent] _streamResponse caught error: $e');
    }
    _llmStreamSub = null;
    return buffer.toString().trim();
  }


  /// Compresses a tool result payload so it fits in the prompt without
  /// bloating every subsequent round. Keeps all keys but truncates long
  /// string values and large list fields to a short summary.
  String _truncateToolResult(Map<String, dynamic> payload, {int maxChars = 600}) {
    final encoded = jsonEncode(payload);
    if (encoded.length <= maxChars) return encoded;

    // Build a trimmed copy: shorten long strings, summarise big lists.
    dynamic trimmed(dynamic value, int depth) {
      if (value is Map<String, dynamic>) {
        return value.map((k, v) => MapEntry(k, trimmed(v, depth + 1)));
      }
      if (value is List) {
        if (value.length > 3) {
          return {'_summary': '${value.length} items', '_first': value.take(2).toList()};
        }
        return {'_list': value.map((e) => trimmed(e, depth + 1)).toList()};
      }
      if (value is String && value.length > 200) {
        return '${value.substring(0, 197)}…';
      }
      return value;
    }

    final slim = payload.map((k, v) => MapEntry(k, trimmed(v, 0)));
    final slimEncoded = jsonEncode(slim);
    if (slimEncoded.length <= maxChars) return slimEncoded;

    // Last resort: raw truncation with a note.
    return '${encoded.substring(0, maxChars - 20)}…[truncated]';
  }


  /// Commits the streamed text as a completed AI message and persists.
  void _finishStreamingWithMessage(
    String text, {
    required String modelName,
    ReasoningTrace? reasoningTrace,
  }) {
    _isStreaming = false;
    _streamingToken = '';
    _llmStreamSub?.cancel();
    _llmStreamSub = null;

    // Stop live TTS if it was running (allows replay button to work for full message)
    _isLiveStreamingTtsEnabled = false;

    final aiMessage = Message(
      sender: 'ai',
      text: text,
      timestamp: DateTime.now(),
      model: modelName,
      reasoningTrace: reasoningTrace,
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
    await muteTts(reason: 'Generation cancelled');
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
        _enqueueSentenceTts(sentence, _ttsSessionId);
      }
    }
  }

  void _flushSentenceBuffer() {
    final leftover = _sentenceBuffer.trim();
    _sentenceBuffer = '';
    if (leftover.isNotEmpty) {
      _enqueueSentenceTts(leftover, _ttsSessionId);
    }
  }

  void _enqueueSentenceTts(String sentence, int sessionId) {
    // Guard: check if TTS is enabled before enqueueing
    if (!_isTtsEnabled) {
      debugPrint('[TTS] Blocked enqueue - TTS disabled: "$sentence"');
      return;
    }
    // Guard: check if session is still active
    if (sessionId != _ttsSessionId) {
      debugPrint(
        '[TTS] Blocked enqueue - stale session $sessionId (current: $_ttsSessionId): "$sentence"',
      );
      return;
    }

    debugPrint(
      '[Sentence Queue TTS] Enqueuing: "$sentence" (session $sessionId)',
    );
    _sentenceQueue.add(_TtsQueueItem(sentence, sessionId));
    _speakNextSentenceSegment();
  }

  Future<void> _speakNextSentenceSegment() async {
    // Guard: check if TTS is enabled before speaking
    if (!_isTtsEnabled) {
      debugPrint('[TTS] Blocked speak - TTS disabled');
      _isSentenceTtsSpeaking = false;
      return;
    }

    if (_isSentenceTtsSpeaking) return;

    // Clean up expired items from the front of the queue
    while (_sentenceQueue.isNotEmpty &&
        _sentenceQueue.first.sessionId != _ttsSessionId) {
      _sentenceQueue.removeAt(0);
    }

    if (_sentenceQueue.isEmpty) return;

    _isSentenceTtsSpeaking = true;
    final item = _sentenceQueue.removeAt(0);

    // Verify session ID before calling speak()
    if (item.sessionId != _ttsSessionId) {
      debugPrint(
        '[TTS] Skipping speak() for stale item from session ${item.sessionId} (current: $_ttsSessionId)',
      );
      _isSentenceTtsSpeaking = false;
      _speakNextSentenceSegment();
      return;
    }

    _activeUtteranceSessionId = _ttsSessionId;

    try {
      debugPrint(
        '[Sentence Queue TTS] Speaking: "${item.sentence}" (session ${item.sessionId})',
      );
      _voiceState = VoiceState.speaking;
      notifyListeners();
      await _ttsService.speak(item.sentence);
    } catch (e) {
      debugPrint('[Sentence Queue TTS] Error speaking: $e');
      _isSentenceTtsSpeaking = false;
      notifyListeners();
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
    _isVoiceSessionActive = true; // Mark voice session as active

    // Validate Whisper model is available
    if (modelManager.activeWhisperModelId == null ||
        modelManager.activeWhisperModel == null) {
      _isVoiceSessionActive = false;
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
        _isVoiceSessionActive = false;
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
          _isVoiceSessionActive = false;
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
      _isVoiceSessionActive = false;
      _voiceState = VoiceState.error;
      _voiceErrorMessage = 'Failed to start speech recognition: $e';
      notifyListeners();
    }
  }

  Future<void> cancelVoiceSession() async {
    if (_voiceState == VoiceState.listening) {
      // Transition to processing state while Whisper transcribes the audio
      _voiceState = VoiceState.processing;
      notifyListeners();
      // This will trigger the onResult callback which populates the input field
      await _sttService.stopListening();
    } else {
      // User cancelled from modal or error state
      _isVoiceSessionActive = false;
      // Stop any TTS that might be playing
      await muteTts(reason: 'Voice session cancelled');
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

    _isTtsEnabled = true;
    _ttsSessionId++; // Start a new session
    _ttsState = TtsState.buffering;
    notifyListeners();

    _sentenceQueue.clear();
    _sentenceBuffer = '';
    _isSentenceTtsSpeaking = false;
    _activeUtteranceSessionId = null; // Fresh replay — reset utterance tracker

    _processSentenceBuffer(msg.text);
    _flushSentenceBuffer();
  }

  Future<void> stopSpeaking() async {
    _ttsSessionId++; // Invalidate active operations & callbacks
    _isTtsEnabled = false;
    _ttsState = TtsState.stopped;
    _activeUtteranceSessionId = null; // No active utterance after stop

    _sentenceQueue.clear();
    _sentenceBuffer = '';
    _isSentenceTtsSpeaking = false;
    _isLiveStreamingTtsEnabled = false;

    _currentlySpeakingMessage = null;
    _voiceState = VoiceState.idle;

    await _ttsService.stop();
    notifyListeners();
  }

  /// COMPREHENSIVE TTS MUTE/STOP
  /// Called when user presses "Stop Speaking", "Mute", or closes microphone dialog
  /// This method ensures ALL speech activity stops immediately with no race conditions
  Future<void> muteTts({String reason = 'User action'}) async {
    debugPrint('[TTS] Muting TTS: $reason');

    _ttsSessionId++; // Invalidate active operations & callbacks
    _isTtsEnabled = false;
    _ttsState = TtsState.muted;
    _activeUtteranceSessionId = null; // No active utterance after mute

    _sentenceQueue.clear();
    _sentenceBuffer = '';
    _isSentenceTtsSpeaking = false;
    _isLiveStreamingTtsEnabled = false;

    _currentlySpeakingMessage = null;
    _currentStreamingMessage = null;
    _voiceState = VoiceState.idle;
    _voiceErrorMessage = '';

    try {
      await _ttsService.stop();
      debugPrint('[TTS] Native TTS stop completed');
    } catch (e) {
      debugPrint('[TTS] Error calling native stop: $e');
    }

    notifyListeners();
  }

  /// RE-ENABLE TTS after muting
  /// Called when user wants to resume TTS operations
  void enableTts({String reason = 'User action'}) {
    if (_isTtsEnabled) return; // Already enabled

    debugPrint('[TTS] Enabling TTS: $reason');
    _isTtsEnabled = true;
    _ttsState = TtsState.idle;
    _voiceState = VoiceState.idle;
    _voiceErrorMessage = '';
    notifyListeners();
  }

  // ===== LIVE STREAMING TTS (Optional feature) =====

  /// Whether the user has enabled live TTS via the button (UI flag)
  bool _isLiveStreamingTtsEnabled = false;
  bool get isLiveStreamingTts => _isLiveStreamingTtsEnabled;

  /// Reference to the message being streamed (for replay button later)
  Message? _currentStreamingMessage;
  Message? get currentStreamingMessage => _currentStreamingMessage;

  /// Check if a message is the one currently streaming
  bool isStreamingMessage(Message msg) => _currentStreamingMessage == msg;

  /// Start live TTS: speak text chunks as they stream in from the LLM
  /// This is independent from replay/sentence-queue TTS
  /// User must manually tap "🔊 Speak Live" button - never automatic
  void startLiveStreamingTts() {
    if (_isLiveStreamingTtsEnabled) return; // Already enabled

    // Stop any existing replay speaking
    if (_currentlySpeakingMessage != null) {
      _ttsService.stop();
    }

    _ttsSessionId++; // Invalidate active operations & callbacks
    _isLiveStreamingTtsEnabled = true;
    _isTtsEnabled = true;
    _ttsState = TtsState.buffering;
    _sentenceQueue.clear();
    _sentenceBuffer = '';
    _isSentenceTtsSpeaking = false;

    debugPrint('[LiveStreamingTts] User enabled live streaming TTS');
    notifyListeners();
  }

  /// Stop live TTS (keeps LLM generation running)
  /// Can be restarted by tapping "Speak Live" again
  Future<void> stopLiveStreamingTts() async {
    if (!_isLiveStreamingTtsEnabled) return;

    _ttsSessionId++; // Invalidate active operations & callbacks
    _isLiveStreamingTtsEnabled = false;
    _isTtsEnabled = false;
    _ttsState = TtsState.stopped;

    _sentenceQueue.clear();
    _sentenceBuffer = '';
    _isSentenceTtsSpeaking = false;

    _currentlySpeakingMessage = null;
    _voiceState = VoiceState.idle;

    await _ttsService.stop();
    debugPrint('[LiveStreamingTts] User stopped live streaming TTS');
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
    _ttsService.setHandlers(onStart: null, onComplete: null, onError: null);
    _ttsService.stop();
    super.dispose();
  }
}
