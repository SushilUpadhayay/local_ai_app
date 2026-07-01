import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_app/models/conversation.dart';
import 'package:local_ai_app/services/context_window_manager.dart';

void main() {
  group('ContextWindowManager recent turn memory', () {
    final manager = ContextWindowManager();

    Message message(String sender, String text) {
      return Message(sender: sender, text: text, timestamp: DateTime(2026));
    }

    test('keeps only the last 3 complete turns before current user', () {
      final context = manager.buildRecentTurnContext([
        message('user', 'old user 1'),
        message('ai', 'old assistant 1'),
        message('user', 'recent user 2'),
        message('ai', 'recent assistant 2'),
        message('user', 'recent user 3'),
        message('ai', 'recent assistant 3'),
        message('user', 'recent user 4'),
        message('ai', 'recent assistant 4'),
        message('user', 'current question'),
      ], turnLimit: 3);

      expect(context, isNot(contains('old user 1')));
      expect(context, isNot(contains('old assistant 1')));
      expect(context, contains('User: recent user 2'));
      expect(context, contains('Assistant: recent assistant 4'));
      expect(context.endsWith('Current User:\ncurrent question'), true);
    });

    test('ignores incomplete previous turns', () {
      final context = manager.buildRecentTurnContext([
        message('user', 'complete user'),
        message('ai', 'complete assistant'),
        message('user', 'orphan previous user'),
        message('user', 'current question'),
      ]);

      expect(context, contains('User: complete user'));
      expect(context, contains('Assistant: complete assistant'));
      expect(context, isNot(contains('orphan previous user')));
      expect(context.endsWith('Current User:\ncurrent question'), true);
    });

    test('returns role-preserving messages for the last 3 turns plus current user', () {
      final messages = manager.getRecentRoleMessages([
        message('user', 'old user 1'),
        message('ai', 'old assistant 1'),
        message('user', 'recent user 2'),
        message('ai', 'recent assistant 2'),
        message('user', 'recent user 3'),
        message('ai', 'recent assistant 3'),
        message('user', 'recent user 4'),
        message('ai', 'recent assistant 4'),
        message('user', 'current question'),
      ], turnLimit: 3);

      expect(messages.map((message) => message.text), [
        'recent user 2',
        'recent assistant 2',
        'recent user 3',
        'recent assistant 3',
        'recent user 4',
        'recent assistant 4',
        'current question',
      ]);
      expect(messages.map((message) => message.sender), [
        'user',
        'ai',
        'user',
        'ai',
        'user',
        'ai',
        'user',
      ]);
    });
  });
}
