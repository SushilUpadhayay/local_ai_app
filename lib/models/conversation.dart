class ReasoningTrace {
  final String matchedTrek;
  final List<String> toolsUsed;
  final List<Map<String, dynamic>> toolCalls;
  final List<Map<String, dynamic>> toolResults;
  final List<String> sourceFiles;
  final int executionTimeMs;

  const ReasoningTrace({
    required this.matchedTrek,
    required this.toolsUsed,
    required this.toolCalls,
    required this.toolResults,
    required this.sourceFiles,
    required this.executionTimeMs,
  });

  bool get hasToolExecution =>
      matchedTrek.isNotEmpty ||
      toolsUsed.isNotEmpty ||
      toolCalls.isNotEmpty ||
      toolResults.isNotEmpty ||
      sourceFiles.isNotEmpty ||
      executionTimeMs > 0;

  Map<String, dynamic> toMap() {
    return {
      'matchedTrek': matchedTrek,
      'toolsUsed': toolsUsed,
      'toolCalls': toolCalls,
      'toolResults': toolResults,
      'sourceFiles': sourceFiles,
      'executionTimeMs': executionTimeMs,
    };
  }

  factory ReasoningTrace.empty() {
    return const ReasoningTrace(
      matchedTrek: '',
      toolsUsed: [],
      toolCalls: [],
      toolResults: [],
      sourceFiles: [],
      executionTimeMs: 0,
    );
  }

  factory ReasoningTrace.fromMap(Map<String, dynamic>? map) {
    if (map == null) return ReasoningTrace.empty();
    return ReasoningTrace(
      matchedTrek: map['matchedTrek'] as String? ?? '',
      toolsUsed: List<String>.from(map['toolsUsed'] ?? const []),
      toolCalls: (map['toolCalls'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      toolResults: (map['toolResults'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      sourceFiles: List<String>.from(map['sourceFiles'] ?? const []),
      executionTimeMs: map['executionTimeMs'] as int? ?? 0,
    );
  }
}

class Message {
  final String sender; // 'user' or 'ai'
  final String text;
  final DateTime timestamp;
  final String? model; // Model used for this response
  final ReasoningTrace? reasoningTrace;

  Message({
    required this.sender,
    required this.text,
    required this.timestamp,
    this.model,
    this.reasoningTrace,
  });

  Map<String, dynamic> toMap() {
    return {
      'sender': sender,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'model': model,
      'reasoningTrace': reasoningTrace?.toMap(),
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      sender: map['sender'] ?? 'user',
      text: map['text'] ?? '',
      timestamp: DateTime.parse(
        map['timestamp'] ?? DateTime.now().toIso8601String(),
      ),
      model: map['model'],
      reasoningTrace: ReasoningTrace.fromMap(
        map['reasoningTrace'] as Map<String, dynamic>?,
      ),
    );
  }
}

class Conversation {
  final String id;
  final String title;
  final String preview;
  final String timeLabel;
  final List<Message> messages;

  Conversation({
    required this.id,
    required this.title,
    required this.preview,
    required this.timeLabel,
    required this.messages,
  });

  Conversation copyWith({
    String? id,
    String? title,
    String? preview,
    String? timeLabel,
    List<Message>? messages,
  }) {
    return Conversation(
      id: id ?? this.id,
      title: title ?? this.title,
      preview: preview ?? this.preview,
      timeLabel: timeLabel ?? this.timeLabel,
      messages: messages ?? this.messages,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'preview': preview,
      'timeLabel': timeLabel,
      'messages': messages.map((m) => m.toMap()).toList(),
    };
  }

  factory Conversation.fromMap(Map<String, dynamic> map) {
    final List<dynamic> msgs = map['messages'] ?? [];
    return Conversation(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      preview: map['preview'] ?? '',
      timeLabel: map['timeLabel'] ?? '',
      messages: msgs.map((m) => Message.fromMap(m)).toList(),
    );
  }
}
