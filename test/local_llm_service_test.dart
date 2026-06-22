import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_app/services/local_llm_service.dart';

void main() {
  group('LocalLlmService router prompt', () {
    test('builds a minimal router-only prompt without trek inference fields by default', () {
      final prompt = LocalLlmService().buildRouterPrompt(
        messages: const [
          {'role': 'user', 'content': 'What is the itinerary?'},
        ],
      );

      expect(prompt, contains('You are a router only.'));
      expect(prompt, contains('Never answer trekking questions.'));
      expect(prompt, contains('Never output JSON.'));
      expect(prompt, contains('Context: No trek is currently selected.'));
      expect(prompt, contains('Type: tool'));
      expect(prompt, contains('Tool: get_trek_details'));
      expect(prompt, contains('Category: route'));
      expect(prompt, isNot(contains('TrekName:')));
      expect(prompt, isNot(contains('ToolName:')));
      expect(prompt, isNot(contains('Question: [user question')));
      expect(prompt, isNot(contains('Available TrekNames:')));
    });

    test('builds prompt with active trek context when hasSelectedTrek is true', () {
      final prompt = LocalLlmService().buildRouterPrompt(
        messages: const [
          {'role': 'user', 'content': 'What is the itinerary?'},
        ],
        hasSelectedTrek: true,
      );

      expect(prompt, contains('Context: A trek IS currently selected.'));
      expect(prompt, isNot(contains('Context: No trek is currently selected.')));
      expect(prompt, contains('User: tell me about everest base camp'));
      expect(prompt, contains('Tool: get_trek_details'));
      expect(prompt, contains('Category: info'));
    });

    test('builds prompt with derived context for last topic and resolved tool', () {
      final prompt = LocalLlmService().buildRouterPrompt(
        messages: const [
          {'role': 'user', 'content': 'What about the cost?'},
        ],
        hasSelectedTrek: true,
        lastResolvedTrek: 'Everest Base Camp',
        lastResolvedTool: 'get_trek_details',
      );

      expect(prompt, contains('Context: A trek IS currently selected.'));
      expect(prompt, contains('Context: Last topic was Everest Base Camp (get_trek_details).'));
    });

    test('builds prompt with derived context for last topic only', () {
      final prompt = LocalLlmService().buildRouterPrompt(
        messages: const [
          {'role': 'user', 'content': 'What about the cost?'},
        ],
        hasSelectedTrek: false,
        lastResolvedTrek: 'Everest Base Camp',
      );

      expect(prompt, contains('Context: No trek is currently selected.'));
      expect(prompt, contains('Context: Last topic was Everest Base Camp.'));
      expect(prompt, isNot(contains('Context: Last resolved tool')));
    });
  });

  group('Router keyword guard heuristic verification', () {
    bool evaluateKeywordGuard({
      required String query,
      required bool hasSelectedTrek,
      required String routerToolOutput,
    }) {
      if (routerToolOutput == 'list_available_treks') {
        final queryLower = query.toLowerCase();
        final hasListingKeywords = queryLower.contains('list') ||
            queryLower.contains('compare') ||
            queryLower.contains('other') ||
            queryLower.contains('options') ||
            queryLower.contains('alternative') ||
            queryLower.contains('which treks') ||
            queryLower.contains('what treks');
        if (hasSelectedTrek && !hasListingKeywords) {
          return true; // Overridden to get_trek_details
        }
      }
      return false; // Not overridden
    }

    test('should override when a trek is selected and query is details-focused', () {
      expect(
        evaluateKeywordGuard(
          query: 'tell me about everest base camp',
          hasSelectedTrek: true,
          routerToolOutput: 'list_available_treks',
        ),
        isTrue,
      );
    });

    test('should NOT override when no trek is selected', () {
      expect(
        evaluateKeywordGuard(
          query: 'tell me about everest base camp',
          hasSelectedTrek: false,
          routerToolOutput: 'list_available_treks',
        ),
        isFalse,
      );
    });

    test('should NOT override when query contains listing keywords', () {
      expect(
        evaluateKeywordGuard(
          query: 'what other treks do you have',
          hasSelectedTrek: true,
          routerToolOutput: 'list_available_treks',
        ),
        isFalse,
      );

      expect(
        evaluateKeywordGuard(
          query: 'compare these options please',
          hasSelectedTrek: true,
          routerToolOutput: 'list_available_treks',
        ),
        isFalse,
      );

      expect(
        evaluateKeywordGuard(
          query: 'what alternative treks are there',
          hasSelectedTrek: true,
          routerToolOutput: 'list_available_treks',
        ),
        isFalse,
      );
    });
  });

  group('LocalLlmService Thread Configuration', () {
    test('defaultThreads matches calculated formula', () {
      final expected = max(1, Platform.numberOfProcessors - 1);
      expect(LocalLlmService.defaultThreads, equals(expected));
    });
  });
}
