import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/conversation.dart';

class ConversationRepository {
  late File _historyFile;

  Future<void> init() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDocDir.path}/history');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _historyFile = File('${dir.path}/conversations.json');
  }

  Future<List<Conversation>> loadConversations() async {
    if (!await _historyFile.exists()) return [];
    try {
      final content = await _historyFile.readAsString();
      final List<dynamic> list = jsonDecode(content);
      return list.map((c) => Conversation.fromMap(c)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveConversations(List<Conversation> conversations) async {
    try {
      final list = conversations.map((c) => c.toMap()).toList();
      await _historyFile.writeAsString(jsonEncode(list));
    } catch (_) {
      // Ignore write errors
    }
  }
}
