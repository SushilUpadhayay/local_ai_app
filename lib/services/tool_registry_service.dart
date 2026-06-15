// ignore_for_file: non_constant_identifier_names
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/conversation.dart';
import 'trek_knowledge_service.dart';

class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  ToolCall({String? id, required this.name, required this.arguments})
    : id = id ?? 'call_${DateTime.now().microsecondsSinceEpoch}';

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'arguments': arguments,
  };

  factory ToolCall.fromMap(Map<String, dynamic> map) {
    final function = map['function'];
    if (function is Map) {
      return ToolCall(
        id: map['id'] as String?,
        name: function['name'] as String? ?? '',
        arguments: _decodeArguments(function['arguments']),
      );
    }
    return ToolCall(
      id: map['id'] as String?,
      name: map['name'] as String? ?? '',
      arguments: _decodeArguments(map['arguments']),
    );
  }

  static Map<String, dynamic> _decodeArguments(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return const {};
  }
}

class ToolExecutionRecord {
  final String toolName;
  final Map<String, dynamic> arguments;
  final DateTime timestamp;
  final int executionTimeMs;
  final List<String> sourceFiles;

  const ToolExecutionRecord({
    required this.toolName,
    required this.arguments,
    required this.timestamp,
    required this.executionTimeMs,
    required this.sourceFiles,
  });

  Map<String, dynamic> toMap() => {
    'toolName': toolName,
    'arguments': arguments,
    'timestamp': timestamp.toIso8601String(),
    'executionTimeMs': executionTimeMs,
    'sourceFiles': sourceFiles,
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

class ToolParseResult {
  final List<ToolCall> calls;
  final bool lookedLikeToolCall;
  final bool parseFailed;

  const ToolParseResult({
    required this.calls,
    required this.lookedLikeToolCall,
    required this.parseFailed,
  });
}

typedef ToolExecutor =
    Map<String, dynamic> Function(Map<String, dynamic> arguments);

class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parametersSchema;
  final ToolExecutor executor;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parametersSchema,
    required this.executor,
  });

  List<String> get requiredParameters =>
      List<String>.from(parametersSchema['required'] ?? const []);

  Map<String, dynamic> toOpenAiToolSchema() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parametersSchema,
    },
  };
}

class ToolValidationResult {
  final bool isValid;
  final String? error;

  const ToolValidationResult.valid() : isValid = true, error = null;
  const ToolValidationResult.invalid(this.error) : isValid = false;
}

class ToolRegistryService {
  final TrekKnowledgeService _trekKnowledgeService;
  final Map<String, ToolDefinition> _tools = {};
  final List<ToolExecutionRecord> _history = [];
  ReasoningTrace _currentTrace = ReasoningTrace.empty();

  ToolRegistryService(this._trekKnowledgeService) {
    _registerTrekTools();
  }

  List<String> get availableToolNames => _tools.keys.toList(growable: false);
  List<Map<String, dynamic>> get toolSchemas =>
      _tools.values.map((tool) => tool.toOpenAiToolSchema()).toList();
  bool requiresTrekName(String toolName) {
    return _tools[toolName]?.requiredParameters.contains('trek_name') ?? false;
  }

  void beginResponseTrace() {
    _currentTrace = ReasoningTrace.empty();
  }

  ReasoningTrace get currentTrace => _currentTrace;
  List<ToolExecutionRecord> get history => List.unmodifiable(_history);
  List<String> get usedTools =>
      _history.map((record) => record.toolName).toSet().toList();

  ToolValidationResult validate(ToolCall call) {
    final definition = _tools[call.name];
    if (definition == null) {
      final result = ToolValidationResult.invalid('Unknown tool: ${call.name}');
      debugPrint('[ToolRegistry] VALIDATE FAIL → ${result.error}');
      return result;
    }

    for (final required in definition.requiredParameters) {
      if (_stringArg(call.arguments, required).isEmpty) {
        final result = ToolValidationResult.invalid(
          'Missing required parameter "$required" for tool ${call.name}',
        );
        debugPrint('[ToolRegistry] VALIDATE FAIL → ${result.error}');
        return result;
      }
    }

    final trekName = _stringArg(call.arguments, 'trek_name');
    if (trekName.isNotEmpty &&
        !_trekKnowledgeService.isValidTrekName(trekName)) {
      final result = ToolValidationResult.invalid(
        'Invalid trekName: $trekName',
      );
      debugPrint('[ToolRegistry] VALIDATE FAIL → ${result.error}');
      return result;
    }

    final category = _stringArg(call.arguments, 'category');
    if (category.isNotEmpty) {
      final allowed = [
        'route',
        'landmarks',
        'villages',
        'hospitals',
        'emergency',
        'transport',
        'itinerary',
      ];
      if (!allowed.contains(category)) {
        final result = ToolValidationResult.invalid(
          'Invalid category: $category. Allowed: ${allowed.join(', ')}',
        );
        debugPrint('[ToolRegistry] VALIDATE FAIL → ${result.error}');
        return result;
      }
    }

    debugPrint(
      '[ToolRegistry] VALIDATE OK  → ${call.name}  args=${call.arguments}',
    );
    return const ToolValidationResult.valid();
  }

  ToolRegistryResult execute(ToolCall call) {
    debugPrint('[ToolRegistry] EXECUTE → ${call.name}  args=${call.arguments}');
    final stopwatch = Stopwatch()..start();
    Map<String, dynamic> payload;

    final validation = validate(call);
    if (!validation.isValid) {
      payload = _standardError(
        call.name,
        validation.error ?? 'Invalid tool call.',
        call.arguments,
      );
      debugPrint('[ToolRegistry] EXECUTE BLOCKED (validation) → ${call.name}');
    } else {
      try {
        payload = _tools[call.name]!.executor(call.arguments);
        debugPrint(
          '[ToolRegistry] EXECUTE SUCCESS → ${call.name}  '
          'success=${payload["success"]}',
        );
      } catch (e, stackTrace) {
        debugPrint('[ToolRegistry] EXECUTE ERROR → ${call.name}: $e');
        debugPrint('$stackTrace');
        payload = _standardError(call.name, e.toString(), call.arguments);
      }
    }

    stopwatch.stop();
    debugPrint(
      '[ToolRegistry] EXECUTE DONE → ${call.name}  '
      '${stopwatch.elapsedMilliseconds}ms',
    );
    final sourceFiles = _sourceFilesFromPayload(payload);
    final record = ToolExecutionRecord(
      toolName: call.name,
      arguments: Map<String, dynamic>.from(call.arguments),
      timestamp: DateTime.now(),
      executionTimeMs: stopwatch.elapsedMilliseconds,
      sourceFiles: sourceFiles,
    );
    _history.add(record);
    _currentTrace = _mergeTrace(_currentTrace, call, payload, record);

    return ToolRegistryResult(
      success: payload['success'] == true,
      toolName: call.name,
      payload: payload,
      record: record,
    );
  }

  List<ToolRegistryResult> executeAll(
    List<ToolCall> calls, {
    int maxSteps = 6,
  }) {
    return calls.take(maxSteps).map(execute).toList();
  }

  bool looksLikeToolCall(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('"tool_calls"') ||
        lower.contains("'tool_calls'") ||
        lower.contains('{tool_calls') ||
        lower.contains('tool_calls')) {
      return true;
    }
    return availableToolNames.any((name) => lower.contains(name.toLowerCase()));
  }

  List<ToolCall> parseToolCalls(String text) {
    return parseToolCallsDetailed(text).calls;
  }

  ToolParseResult parseToolCallsDetailed(String text) {
    final trimmed = text.trim();
    final lookedLikeToolCall = looksLikeToolCall(trimmed);
    if (trimmed.isEmpty) {
      return const ToolParseResult(
        calls: [],
        lookedLikeToolCall: false,
        parseFailed: false,
      );
    }

    debugPrint('[ToolRegistry] RAW LLM OUTPUT:\n$trimmed');

    // 1. XML-tagged tool calls take highest priority.
    final taggedCalls = RegExp(
      r'<tool_call>\s*(\{[\s\S]*?\})\s*</tool_call>',
      caseSensitive: false,
    ).allMatches(trimmed);
    final calls = <ToolCall>[];
    for (final match in taggedCalls) {
      calls.addAll(_parseToolCallsFromJson(match.group(1)!));
    }
    if (calls.isNotEmpty) {
      debugPrint('[ToolRegistry] PARSED ${calls.length} call(s) via XML tags.');
      return ToolParseResult(
        calls: calls,
        lookedLikeToolCall: true,
        parseFailed: false,
      );
    }

    // 2. Extract first well-formed JSON object (brace-depth matched).
    var jsonText = _extractJsonObject(trimmed);

    if (jsonText == null) {
      // 3. Attempt to repair partial / truncated JSON before giving up.
      debugPrint(
        '[ToolRegistry] JSON extraction failed — attempting repair...',
      );
      jsonText = _attemptJsonRepair(trimmed);
    }

    if (jsonText == null) {
      debugPrint('[ToolRegistry] No tool call JSON found in LLM output.');
      return ToolParseResult(
        calls: const [],
        lookedLikeToolCall: lookedLikeToolCall,
        parseFailed: lookedLikeToolCall,
      );
    }

    // 4. Warn when the model mixed tool JSON with prose (Req 5).
    if (_hasMixedOutput(trimmed, jsonText)) {
      debugPrint(
        '[ToolRegistry] WARNING: mixed output detected — '
        'tool JSON followed by prose. Discarding prose.',
      );
    }

    final parsed = _parseToolCallsFromJson(jsonText);
    debugPrint(
      '[ToolRegistry] PARSED ${parsed.length} call(s): '
      '${parsed.map((c) => c.name).join(", ")}',
    );
    return ToolParseResult(
      calls: parsed,
      lookedLikeToolCall: lookedLikeToolCall || parsed.isNotEmpty,
      parseFailed: parsed.isEmpty && lookedLikeToolCall,
    );
  }

  void _register(ToolDefinition definition) {
    _tools[definition.name] = definition;
  }

  void _registerTrekTools() {
    final tools = <ToolDefinition>[
      ToolDefinition(
        name: 'get_trek_overview',
        description:
            'Returns trek overview, difficulty, altitude, permits, seasons, and duration.',
        parametersSchema: _objectSchema(const {}, const []),
        executor: (args) => _trekKnowledgeService.get_trek_overview(
          _stringArg(args, 'trek_name'),
        ),
      ),
      ToolDefinition(
        name: 'get_trek_details',
        description:
            'Returns specific details for a trek like route, landmarks, villages, hospitals, emergency, transport or itinerary.',
        parametersSchema: _objectSchema(
          {
            'category': {
              'type': 'string',
              'enum': [
                'route',
                'landmarks',
                'villages',
                'hospitals',
                'emergency',
                'transport',
                'itinerary',
              ],
              'description': 'The category of details to retrieve.',
            },
          },
          const ['category'],
        ),
        executor: (args) => _trekKnowledgeService.get_trek_details(
          _stringArg(args, 'trek_name'),
          _stringArg(args, 'category'),
        ),
      ),
      ToolDefinition(
        name: 'get_trek_faq',
        description: 'Returns the closest FAQ answer for a user question.',
        parametersSchema: _objectSchema(
          {
            'question': {
              'type': 'string',
              'description':
                  'The user question to match against offline trek FAQs.',
            },
          },
          const ['question'],
        ),
        executor: (args) => _trekKnowledgeService.get_trek_faq(
          _stringArg(args, 'trek_name'),
          _stringArg(args, 'question'),
        ),
      ),
      ToolDefinition(
        name: 'list_available_treks',
        description:
            'Lists all treks currently available in the offline database.',
        parametersSchema: _objectSchema(const {}, const []),
        executor: (_) => _trekKnowledgeService.list_available_treks(),
      ),
      ToolDefinition(
        name: 'get_used_tools',
        description: 'Returns tool names used so far in this app session.',
        parametersSchema: _objectSchema(const {}, const []),
        executor: (_) => {
          'success': true,
          'tool': 'get_used_tools',
          'trek_name': 'session',
          'source_file': 'runtime',
          'data': {'tools': usedTools},
        },
      ),
      ToolDefinition(
        name: 'get_tool_history',
        description:
            'Returns the offline tool execution history for this app session.',
        parametersSchema: _objectSchema(const {}, const []),
        executor: (_) => {
          'success': true,
          'tool': 'get_tool_history',
          'trek_name': 'session',
          'source_file': 'runtime',
          'data': {'history': _history.map((r) => r.toMap()).toList()},
        },
      ),
      ToolDefinition(
        name: 'get_reasoning_trace',
        description:
            'Returns the current response reasoning metadata without chain-of-thought.',
        parametersSchema: _objectSchema(const {}, const []),
        executor: (_) => {
          'success': true,
          'tool': 'get_reasoning_trace',
          'trek_name': 'response',
          'source_file': 'runtime',
          'data': _currentTrace.toMap(),
        },
      ),
    ];

    for (final tool in tools) {
      _register(tool);
    }
  }

  Map<String, dynamic> _objectSchema(
    Map<String, dynamic> properties,
    List<String> required,
  ) => {
    'type': 'object',
    'properties': properties,
    'required': required,
    'additionalProperties': false,
  };

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
      'trek_name': arguments['trek_name'] ?? 'none',
      'source_file': 'runtime',
      'error': error,
      'data': {},
    };
  }

  List<String> _sourceFilesFromPayload(Map<String, dynamic> payload) {
    final files = <String>{};
    final sourceFile = payload['source_file'];
    final sourceFiles = payload['source_files'];
    if (sourceFile is String && sourceFile.isNotEmpty) files.add(sourceFile);
    if (sourceFiles is List) {
      files.addAll(sourceFiles.whereType<String>().where((f) => f.isNotEmpty));
    }
    return files.isEmpty ? const ['runtime'] : files.toList();
  }

  ReasoningTrace _mergeTrace(
    ReasoningTrace trace,
    ToolCall call,
    Map<String, dynamic> payload,
    ToolExecutionRecord record,
  ) {
    final matchedTrek = payload['trek_name'] as String? ?? trace.matchedTrek;
    final tools = {...trace.toolsUsed, record.toolName}.toList();
    final files = {...trace.sourceFiles, ...record.sourceFiles}.toList();
    final resultPreview = Map<String, dynamic>.from(payload);
    final data = resultPreview['data'];
    if (data is Map && data.length > 8) {
      resultPreview['data'] = {
        'summary': 'Large tool result omitted from reasoning panel.',
        'keys': data.keys.toList(),
      };
    }

    return ReasoningTrace(
      matchedTrek:
          matchedTrek == 'all' ||
              matchedTrek == 'session' ||
              matchedTrek == 'response'
          ? trace.matchedTrek
          : matchedTrek,
      toolsUsed: tools,
      toolCalls: [...trace.toolCalls, call.toMap()],
      toolResults: [...trace.toolResults, resultPreview],
      sourceFiles: files,
      executionTimeMs: trace.executionTimeMs + record.executionTimeMs,
    );
  }

  List<ToolCall> _parseToolCallsFromJson(String jsonText) {
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) {
        debugPrint(
          '[ToolRegistry] JSON decoded but not a Map: '
          '${decoded.runtimeType}',
        );
        return const [];
      }
      final map = Map<String, dynamic>.from(decoded);
      final rawCalls = map['tool_calls'] ?? map['toolCalls'];
      if (rawCalls is List) {
        final result = rawCalls
            .whereType<Map>()
            .map((item) => ToolCall.fromMap(Map<String, dynamic>.from(item)))
            .where((call) => call.name.isNotEmpty)
            .toList();
        debugPrint(
          '[ToolRegistry] Decoded ${result.length} call(s): '
          '${result.map((c) => c.name).join(", ")}',
        );
        return result;
      }
      if (map['name'] is String || map['function'] is Map) {
        final call = ToolCall.fromMap(map);
        if (call.name.isNotEmpty) {
          debugPrint('[ToolRegistry] Single call decoded: ${call.name}');
          return [call];
        }
        return const [];
      }
      debugPrint(
        '[ToolRegistry] JSON structure not recognised as tool call. '
        'Keys: ${map.keys.toList()}',
      );
      return const [];
    } catch (e) {
      debugPrint('[ToolRegistry] Could not parse tool calls from JSON: $e');
      debugPrint('[ToolRegistry] Attempted JSON: $jsonText');
      return const [];
    }
  }

  // Extracts the first well-formed JSON object from [text] using proper
  // brace-depth tracking, so prose that follows the JSON block cannot cause
  // the wrong closing brace to be selected (unlike a naive lastIndexOf).
  String? _extractJsonObject(String text) {
    final start = text.indexOf('{');
    if (start == -1) return null;

    int depth = 0;
    bool inString = false;
    bool escaped = false;

    for (int i = start; i < text.length; i++) {
      final c = text[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == '\\' && inString) {
        escaped = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;

      if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) {
          return text.substring(start, i + 1);
        }
      }
    }
    return null; // Incomplete JSON — caller should attempt repair.
  }

  // Returns true when [fullText] contains significant non-JSON content
  // alongside the [extractedJson] block — i.e. the model mixed tool
  // output with prose text (Requirement 5).
  bool _hasMixedOutput(String fullText, String extractedJson) {
    final remainder = fullText.replaceFirst(extractedJson, '').trim();
    return remainder.length > 20;
  }

  // Attempts to repair partial / truncated JSON that small models occasionally
  // produce when the context window runs out mid-generation.
  // Strategy: close any open string literals, then close open arrays and
  // objects in LIFO order, then validate with jsonDecode.
  String? _attemptJsonRepair(String text) {
    final start = text.indexOf('{');
    if (start == -1) return null;

    final snippet = text.substring(start);
    int openBraces = 0;
    int openBrackets = 0;
    bool inString = false;
    bool escaped = false;

    for (int i = 0; i < snippet.length; i++) {
      final c = snippet[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == '\\' && inString) {
        escaped = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;

      if (c == '{') {
        openBraces++;
      } else if (c == '}') {
        openBraces--;
      } else if (c == '[') {
        openBrackets++;
      } else if (c == ']') {
        openBrackets--;
      }
    }

    // Already balanced — just return the snippet from the opening brace.
    if (openBraces == 0 && openBrackets == 0) return snippet;

    final repaired = StringBuffer(snippet);
    if (inString) repaired.write('"'); // close open string
    for (int i = 0; i < openBrackets; i++) {
      repaired.write(']'); // close arrays
    }
    for (int i = 0; i < openBraces; i++) {
      repaired.write('}'); // close objects
    }

    final result = repaired.toString();
    debugPrint('[ToolRegistry] Attempting JSON repair: $result');

    try {
      jsonDecode(result); // Verify the repair produced valid JSON.
      return result;
    } catch (_) {
      debugPrint('[ToolRegistry] Repair failed — JSON still invalid.');
      return null;
    }
  }
}
