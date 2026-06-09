import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/conversation.dart';
import 'trek_knowledge_service.dart';

class ToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  const ToolCall({required this.name, required this.arguments});

  Map<String, dynamic> toMap() => {'name': name, 'arguments': arguments};

  factory ToolCall.fromMap(Map<String, dynamic> map) {
    return ToolCall(
      name: map['name'] as String? ?? '',
      arguments: Map<String, dynamic>.from(map['arguments'] ?? const {}),
    );
  }
}

class ToolExecutionRecord {
  final String toolName;
  final Map<String, dynamic> arguments;
  final DateTime timestamp;
  final int executionTimeMs;
  final String sourceFile;

  const ToolExecutionRecord({
    required this.toolName,
    required this.arguments,
    required this.timestamp,
    required this.executionTimeMs,
    required this.sourceFile,
  });

  Map<String, dynamic> toMap() => {
    'toolName': toolName,
    'arguments': arguments,
    'timestamp': timestamp.toIso8601String(),
    'executionTimeMs': executionTimeMs,
    'sourceFile': sourceFile,
  };
}

class ToolRegistryResult {
  final bool success;
  final String toolName;
  final Map<String, dynamic> payload;
  final ToolExecutionRecord record;

  const ToolRegistryResult({
    required this.success,
    required this.toolName,
    required this.payload,
    required this.record,
  });
}

typedef _ToolExecutor =
    Map<String, dynamic> Function(Map<String, dynamic> arguments);

class ToolRegistryService {
  final TrekKnowledgeService _trekKnowledgeService;
  final Map<String, _ToolExecutor> _tools = {};
  final List<ToolExecutionRecord> _history = [];
  ReasoningTrace _currentTrace = ReasoningTrace.empty();

  ToolRegistryService(this._trekKnowledgeService) {
    _registerTrekTools();
  }

  List<String> get availableToolNames => _tools.keys.toList(growable: false);

  void beginResponseTrace() {
    _currentTrace = ReasoningTrace.empty();
  }

  ReasoningTrace get currentTrace => _currentTrace;

  List<ToolExecutionRecord> get history => List.unmodifiable(_history);

  List<String> get usedTools =>
      _history.map((record) => record.toolName).toSet().toList();

  bool validate(ToolCall call) {
    if (!_tools.containsKey(call.name)) return false;
    if (call.name == 'list_available_treks' ||
        call.name == 'get_used_tools' ||
        call.name == 'get_tool_history' ||
        call.name == 'get_reasoning_trace') {
      return true;
    }
    if (call.name == 'search_trek') {
      return _stringArg(call.arguments, 'trekName').isNotEmpty ||
          _stringArg(call.arguments, 'query').isNotEmpty;
    }
    if (call.name == 'get_faq_answer') {
      return _stringArg(call.arguments, 'trekId').isNotEmpty &&
          _stringArg(call.arguments, 'question').isNotEmpty;
    }
    return _stringArg(call.arguments, 'trekId').isNotEmpty;
  }

  ToolRegistryResult execute(ToolCall call) {
    final stopwatch = Stopwatch()..start();
    Map<String, dynamic> payload;

    if (!validate(call)) {
      payload = _standardError(
        call.name,
        'Invalid or unsupported tool call.',
        call.arguments,
      );
    } else {
      try {
        payload = _tools[call.name]!(call.arguments);
      } catch (e, stackTrace) {
        debugPrint('[ToolRegistryService] Tool ${call.name} failed: $e');
        debugPrint('$stackTrace');
        payload = _standardError(call.name, e.toString(), call.arguments);
      }
    }

    stopwatch.stop();
    final sourceFile = payload['source_file'] as String? ?? 'runtime';
    final record = ToolExecutionRecord(
      toolName: call.name,
      arguments: Map<String, dynamic>.from(call.arguments),
      timestamp: DateTime.now(),
      executionTimeMs: stopwatch.elapsedMilliseconds,
      sourceFile: sourceFile,
    );
    _history.add(record);
    _currentTrace = _mergeTrace(_currentTrace, payload, record);

    final success = payload['success'] == true;
    return ToolRegistryResult(
      success: success,
      toolName: call.name,
      payload: payload,
      record: record,
    );
  }

  List<ToolRegistryResult> executeAll(
    List<ToolCall> calls, {
    int maxSteps = 3,
  }) {
    final results = <ToolRegistryResult>[];
    for (final call in calls.take(maxSteps)) {
      results.add(execute(call));
    }
    return results;
  }

  ToolCall? callFromDetectedIntent(Map<String, dynamic>? intent, String query) {
    if (intent == null || intent['tool'] == null) return null;
    final tool = intent['tool'] as String;
    final trekId = intent['trekId'] as String? ?? '';
    final arguments = <String, dynamic>{};

    if (tool == 'search_trek') {
      arguments['trekName'] = trekId == 'all' ? query : trekId;
    } else if (tool == 'get_faq_answer') {
      arguments['trekId'] = trekId;
      arguments['question'] = intent['raw_question'] as String? ?? query;
    } else if (tool != 'list_available_treks') {
      arguments['trekId'] = trekId;
    }

    return ToolCall(name: tool, arguments: arguments);
  }

  List<ToolCall> parseToolSelection(String text) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return const [];

    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start == -1 || end <= start) return const [];

    try {
      final decoded = jsonDecode(cleaned.substring(start, end + 1));
      if (decoded is! Map<String, dynamic>) return const [];
      if (decoded['tool_required'] != true) return const [];

      final rawCalls = decoded['tool_calls'];
      if (rawCalls is List) {
        return rawCalls
            .whereType<Map>()
            .map((map) => ToolCall.fromMap(Map<String, dynamic>.from(map)))
            .where(validate)
            .toList();
      }

      final name = decoded['tool'] as String?;
      if (name == null) return const [];
      final call = ToolCall(
        name: name,
        arguments: Map<String, dynamic>.from(decoded['arguments'] ?? const {}),
      );
      return validate(call) ? [call] : const [];
    } catch (e) {
      debugPrint('[ToolRegistryService] Could not parse tool selection: $e');
      return const [];
    }
  }

  void _registerTrekTools() {
    _tools['search_trek'] = (args) => _trekKnowledgeService.search_trek(
      _stringArg(args, 'trekName', fallbackKey: 'query'),
    );
    _tools['get_trek_info'] = (args) =>
        _trekKnowledgeService.get_trek_info(_stringArg(args, 'trekId'));
    _tools['get_route_info'] = (args) =>
        _trekKnowledgeService.get_route_info(_stringArg(args, 'trekId'));
    _tools['get_landmarks'] = (args) =>
        _trekKnowledgeService.get_landmarks(_stringArg(args, 'trekId'));
    _tools['get_villages'] = (args) =>
        _trekKnowledgeService.get_villages(_stringArg(args, 'trekId'));
    _tools['get_health_posts'] = (args) =>
        _trekKnowledgeService.get_health_posts(_stringArg(args, 'trekId'));
    _tools['get_emergency_info'] = (args) =>
        _trekKnowledgeService.get_emergency_info(_stringArg(args, 'trekId'));
    _tools['get_transport_info'] = (args) =>
        _trekKnowledgeService.get_transport_info(_stringArg(args, 'trekId'));
    _tools['get_faq_answer'] = (args) => _trekKnowledgeService.get_faq_answer(
      _stringArg(args, 'trekId'),
      _stringArg(args, 'question'),
    );
    _tools['list_available_treks'] = (_) =>
        _trekKnowledgeService.list_available_treks();
    _tools['get_used_tools'] = (_) => {
      'success': true,
      'tool': 'get_used_tools',
      'trekId': 'session',
      'source_file': 'runtime',
      'data': {'tools': usedTools},
    };
    _tools['get_tool_history'] = (_) => {
      'success': true,
      'tool': 'get_tool_history',
      'trekId': 'session',
      'source_file': 'runtime',
      'data': {'history': _history.map((r) => r.toMap()).toList()},
    };
    _tools['get_reasoning_trace'] = (_) => {
      'success': true,
      'tool': 'get_reasoning_trace',
      'trekId': 'response',
      'source_file': 'runtime',
      'data': _currentTrace.toMap(),
    };
  }

  String _stringArg(
    Map<String, dynamic> args,
    String key, {
    String? fallbackKey,
  }) {
    final value = args[key] ?? (fallbackKey != null ? args[fallbackKey] : null);
    return value?.toString().trim() ?? '';
  }

  Map<String, dynamic> _standardError(
    String tool,
    String error,
    Map<String, dynamic> arguments,
  ) {
    return {
      'success': false,
      'tool': tool,
      'trekId': arguments['trekId'] ?? 'none',
      'source_file': 'runtime',
      'error': error,
      'data': {},
    };
  }

  ReasoningTrace _mergeTrace(
    ReasoningTrace trace,
    Map<String, dynamic> payload,
    ToolExecutionRecord record,
  ) {
    final matchedTrek = payload['trekId'] as String? ?? trace.matchedTrek;
    final tools = {...trace.toolsUsed, record.toolName}.toList();
    final files = {
      ...trace.sourceFiles,
      if (record.sourceFile.isNotEmpty) record.sourceFile,
    }.toList();

    return ReasoningTrace(
      matchedTrek: matchedTrek == 'all' || matchedTrek == 'session'
          ? trace.matchedTrek
          : matchedTrek,
      toolsUsed: tools,
      sourceFiles: files,
      executionTimeMs: trace.executionTimeMs + record.executionTimeMs,
    );
  }
}
