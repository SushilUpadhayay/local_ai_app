import 'dart:async';
import 'dart:io';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:flutter/foundation.dart';

abstract class LlmService {
  Future<void> loadModel(String modelPath, {int contextWindow = 2048});
  Future<void> unloadModel();
  Stream<String> generate(String prompt);
  void cancelGeneration();
  bool get isModelLoaded;
}

class LocalLlmService implements LlmService {
  LlamaEngine? _engine;
  EngineSession? _session;
  bool _isLoaded = false;
  bool _isLoading = false;
  bool _isLoadCancelled = false;
  StreamSubscription<GenerationEvent>? _activeGenSub;

  @override
  bool get isModelLoaded => _isLoaded;

  @override
  Future<void> loadModel(String modelPath, {int contextWindow = 2048}) async {
    if (_isLoading) return;
    _isLoading = true;
    _isLoadCancelled = false;

    // 1. Unload any existing model/engine first to release RAM
    await _cleanUpResources();

    try {
      if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
        throw UnsupportedError('Real local inference is only supported on Android, iOS, macOS, Windows, or Linux.');
      }

      final file = File(modelPath);
      if (!await file.exists() || await file.length() == 0) {
        throw FileSystemException('GGUF model file not found or corrupted.', modelPath);
      }

      if (_isLoadCancelled) {
        throw Exception('Model loading was cancelled.');
      }

      // 2. Initialize the LlamaEngine worker isolate
      debugPrint('Spawning LlamaEngine with model path: $modelPath (contextWindow: $contextWindow)...');
      
      final LlamaEngine engine;
      if (Platform.isIOS) {
        engine = await LlamaEngine.spawnFromProcess(
          modelParams: ModelParams(path: modelPath),
          contextParams: ContextParams(nCtx: contextWindow),
        );
      } else {
        final libPath = Platform.isAndroid
            ? 'libllama.so'
            : Platform.isWindows
                ? 'llama.dll'
                : Platform.isMacOS
                    ? 'libllama.dylib'
                    : Platform.isLinux
                        ? 'libllama.so'
                        : '';
        engine = await LlamaEngine.spawn(
          libraryPath: libPath,
          modelParams: ModelParams(path: modelPath),
          contextParams: ContextParams(nCtx: contextWindow),
        );
      }

      if (_isLoadCancelled) {
        engine.dispose();
        throw Exception('Model loading was cancelled.');
      }

      _engine = engine;

      // 3. Create the off-thread session
      debugPrint('Creating session for engine...');
      _session = await engine.createSession();

      if (_isLoadCancelled) {
        await unloadModel();
        throw Exception('Model loading was cancelled.');
      }

      _isLoaded = true;
      _isLoading = false;

      // 4. Perform a model warmup to reduce first-response latency
      debugPrint('Performing model warmup prompt...');
      await _warmup();
      debugPrint('Model loaded and warmed up successfully.');

    } catch (e) {
      _isLoaded = false;
      _isLoading = false;
      _session = null;
      _engine?.dispose();
      _engine = null;
      rethrow;
    }
  }

  Future<void> _cleanUpResources() async {
    _activeGenSub?.cancel();
    _activeGenSub = null;

    if (_session != null) {
      try {
        await _session!.dispose();
      } catch (e) {
        debugPrint('Error disposing session: $e');
      }
      _session = null;
    }

    if (_engine != null) {
      debugPrint('Disposing engine...');
      await _engine!.dispose();
      _engine = null;
    }
  }

  @override
  Future<void> unloadModel() async {
    _isLoaded = false;
    _isLoading = false;
    _isLoadCancelled = true;
    
    await _cleanUpResources();
    // Force garbage collection hint
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  Stream<String> generate(String prompt) {
    if (!_isLoaded || _session == null) {
      return Stream.error(StateError('No model loaded. You must load a model before generating text.'));
    }

    final controller = StreamController<String>(
      onCancel: () {
        _activeGenSub?.cancel();
        _activeGenSub = null;
      },
    );
    
    _activeGenSub?.cancel();
    
    Future.microtask(() async {
      try {
        // Clear session KV cache to start fresh with new context prompt
        await _session!.clear();
        
        final eventStream = _session!.generate(
          prompt: prompt,
          maxTokens: 512,
        );

        _activeGenSub = eventStream.listen(
          (event) {
            if (event is TokenEvent) {
              controller.add(event.text);
            } else if (event is DoneEvent) {
              if (event.trailingText.isNotEmpty) {
                controller.add(event.trailingText);
              }
              controller.close();
            }
          },
          onError: (err) {
            controller.addError(err);
            controller.close();
          },
          onDone: () {
            if (!controller.isClosed) {
              controller.close();
            }
          },
          cancelOnError: true,
        );
      } catch (e) {
        controller.addError(e);
        controller.close();
      }
    });

    return controller.stream;
  }

  @override
  void cancelGeneration() {
    _activeGenSub?.cancel();
    _activeGenSub = null;
  }

  Future<void> _warmup() async {
    if (_session == null) return;
    try {
      final warmupStream = _session!.generate(prompt: '\n', maxTokens: 1);
      await for (final _ in warmupStream) {
        // consume the single token stream to trigger warm up
      }
    } catch (e) {
      debugPrint('Warmup warning: $e');
    }
  }
}
