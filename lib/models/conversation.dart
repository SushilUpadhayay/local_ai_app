class Message {
  final String sender; // 'user' or 'ai'
  final String text;
  final DateTime timestamp;
  final String? model; // Model used for this response

  Message({
    required this.sender,
    required this.text,
    required this.timestamp,
    this.model,
  });

  Map<String, dynamic> toMap() {
    return {
      'sender': sender,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'model': model,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      sender: map['sender'] ?? 'user',
      text: map['text'] ?? '',
      timestamp: DateTime.parse(map['timestamp'] ?? DateTime.now().toIso8601String()),
      model: map['model'],
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
