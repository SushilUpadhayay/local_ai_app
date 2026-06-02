import '../models/conversation.dart';

class ContextWindowManager {
  // Approximate token count based on typical character length (~4 chars per token)
  int estimateTokenCount(String text) {
    return (text.length / 4.0).ceil();
  }

  // Construct a history payload that fits within the model's context window.
  // Starting from the latest message, it prepends history until the token limit is reached.
  List<Message> getContextMessages(List<Message> fullHistory, int contextLimit) {
    if (fullHistory.isEmpty) return [];

    final List<Message> contextList = [];
    int currentTokens = 0;

    // Iterate backwards from latest to oldest
    for (int i = fullHistory.length - 1; i >= 0; i--) {
      final msg = fullHistory[i];
      final estimatedTokens = estimateTokenCount(msg.text) + 20; // adding 20 tokens margin for structure/role tokens

      if (currentTokens + estimatedTokens > contextLimit) {
        break; // Stop including older history if it overflows context window
      }

      contextList.insert(0, msg);
      currentTokens += estimatedTokens;
    }

    return contextList;
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
}
