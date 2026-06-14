import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_app/services/tool_registry_service.dart';
import 'package:local_ai_app/services/trek_knowledge_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ToolRegistryService native tool architecture', () {
    late TrekKnowledgeService knowledgeService;
    late ToolRegistryService registry;

    setUp(() async {
      knowledgeService = TrekKnowledgeService();
      await knowledgeService.initialize();
      registry = ToolRegistryService(knowledgeService);
    });

    test('generates OpenAI-compatible tool schemas from registry', () {
      final schemas = registry.toolSchemas;
      final getTrekInfo = schemas.firstWhere(
        (schema) => schema['function']['name'] == 'get_trek_overview',
      );

      expect(getTrekInfo['type'], 'function');
      expect(getTrekInfo['function']['description'], isNotEmpty);
      expect(
        getTrekInfo['function']['parameters']['required'],
        contains('trek_name'),
      );
    });

    test('executes multiple tool calls and records reasoning trace', () {
      registry.beginResponseTrace();
      final results = registry.executeAll([
        ToolCall(
          name: 'get_trek_overview',
          arguments: {'trek_name': 'annapurna_base_camp'},
        ),
        ToolCall(
          name: 'get_trek_overview',
          arguments: {'trek_name': 'everest_base_camp'},
        ),
      ]);

      expect(results, hasLength(2));
      expect(results.every((result) => result.success), true);
      expect(registry.currentTrace.toolsUsed, contains('get_trek_overview'));
      expect(registry.currentTrace.toolCalls, hasLength(2));
      expect(
        registry.currentTrace.sourceFiles,
        contains('annapurna_base_camp_trek_data.json'),
      );
    });

    test('rejects invalid trekName safely', () {
      final result = registry.execute(
        ToolCall(
          name: 'get_trek_overview',
          arguments: {'trek_name': 'unknown_trek'},
        ),
      );

      expect(result.success, false);
      expect(result.payload['error'], contains('Invalid trek_name'));
    });

    test('detects malformed tool calls separately from final answers', () {
      final malformed = registry.parseToolCallsDetailed(
        'I will call tool_calls get_trek_overview for annapurna_base_camp',
      );

      expect(malformed.lookedLikeToolCall, true);
      expect(malformed.parseFailed, true);
      expect(malformed.calls, isEmpty);

      final finalAnswer = registry.parseToolCallsDetailed(
        'Hello! How can I help you today?',
      );

      expect(finalAnswer.lookedLikeToolCall, false);
      expect(finalAnswer.parseFailed, false);
      expect(finalAnswer.calls, isEmpty);
    });
  });
}
