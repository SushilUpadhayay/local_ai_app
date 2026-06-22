import '../models/conversation.dart';

class ContextWindowManager {
  static const int defaultTurnLimit = 3; // Three previous chats
  static const int pass2TurnLimit = 2; // Two previous chats

  // Approximate token count based on typical character length (~4 chars per token).
  // Kept for diagnostics and future budgeting; prompt memory is turn-limited.
  int estimateTokenCount(String text) {
    return (text.length / 4.0).ceil();
  }

  String buildRecentTurnContext(
    List<Message> fullHistory, {
    int turnLimit = defaultTurnLimit,
  }) {
    final currentUserMessage = _currentUserMessage(fullHistory);
    final previousMessages = currentUserMessage == null
        ? fullHistory
        : fullHistory.take(fullHistory.length - 1).toList();
    final turns = _completeTurns(previousMessages);
    final recentTurns = turns.length <= turnLimit
        ? turns
        : turns.sublist(turns.length - turnLimit);

    final buffer = StringBuffer();
    for (final turn in recentTurns) {
      buffer
        ..writeln('User: ${turn.user.text}')
        ..writeln('Assistant: ${turn.assistant.text}')
        ..writeln();
    }

    if (currentUserMessage != null) {
      buffer
        ..writeln('Current User:')
        ..write(currentUserMessage.text);
    }

    return buffer.toString().trimRight();
  }

  List<Message> getRecentRoleMessages(
    List<Message> fullHistory, {
    int turnLimit = defaultTurnLimit,
  }) {
    final currentUserMessage = _currentUserMessage(fullHistory);
    final previousMessages = currentUserMessage == null
        ? fullHistory
        : fullHistory.take(fullHistory.length - 1).toList();
    final turns = _completeTurns(previousMessages);
    final recentTurns = turns.length <= turnLimit
        ? turns
        : turns.sublist(turns.length - turnLimit);

    return [
      for (final turn in recentTurns) ...[turn.user, turn.assistant],
      ?currentUserMessage,
    ];
  }

  List<Message> getPreviousTurnRoleMessages(
    List<Message> fullHistory, {
    int turnLimit = pass2TurnLimit,
  }) {
    final currentUserMessage = _currentUserMessage(fullHistory);
    final previousMessages = currentUserMessage == null
        ? fullHistory
        : fullHistory.take(fullHistory.length - 1).toList();
    final turns = _completeTurns(previousMessages);
    final recentTurns = turns.length <= turnLimit
        ? turns
        : turns.sublist(turns.length - turnLimit);

    return [
      for (final turn in recentTurns) ...[turn.user, turn.assistant],
    ];
  }

  // Build a standard prompt using ChatML format for the llama.cpp engine
  String buildChatMLPrompt(List<Message> messages, String systemInstruction) {
    final buffer = StringBuffer();
    
    // Add system instruction
    buffer.write('<|im_start|>system\n$systemInstruction<|im_end|>\n');

    for (final msg in messages) {
      final role = msg.sender == 'user' ? 'user' : 'assistant';
      buffer.write('<|im_start|>$role\n${msg.text}<|im_end|>\n');
    }

    // Append prompt tail for model response generation
    buffer.write('<|im_start|>assistant\n');
    return buffer.toString();
  }

  Message? _currentUserMessage(List<Message> fullHistory) {
    if (fullHistory.isEmpty) return null;
    final latest = fullHistory.last;
    return latest.sender == 'user' ? latest : null;
  }

  List<_ConversationTurn> _completeTurns(List<Message> messages) {
    final turns = <_ConversationTurn>[];
    for (var i = 0; i < messages.length - 1; i++) {
      final user = messages[i];
      final assistant = messages[i + 1];
      if (user.sender == 'user' && assistant.sender != 'user') {
        turns.add(_ConversationTurn(user: user, assistant: assistant));
        i++;
      }
    }
    return turns;
  }
}

class _ConversationTurn {
  final Message user;
  final Message assistant;

  const _ConversationTurn({required this.user, required this.assistant});
}
