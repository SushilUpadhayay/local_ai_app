import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_app/models/tool_result.dart';
import 'package:local_ai_app/services/tool_registry_service.dart';
import 'package:local_ai_app/services/tool_result_prompt_builder.dart';
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
        (schema) => schema['function']['name'] == 'get_trek_details',
      );

      expect(getTrekInfo['type'], 'function');
      expect(getTrekInfo['function']['description'], isNotEmpty);
      expect(
        getTrekInfo['function']['parameters']['required'],
        contains('trek_name'),
      );
      expect(
        getTrekInfo['function']['parameters']['required'],
        contains('category'),
      );
    });

    test('executes multiple tool calls and records reasoning trace', () {
      registry.beginResponseTrace();
      final results = registry.executeAll([
        ToolCall(
          name: 'get_trek_details',
          arguments: {'trek_name': 'annapurna_base_camp', 'category': 'info'},
        ),
        ToolCall(
          name: 'get_trek_details',
          arguments: {'trek_name': 'everest_base_camp', 'category': 'route'},
        ),
      ]);

      expect(results, hasLength(2));
      expect(results.every((result) => result.success), true);
      expect(registry.currentTrace.toolsUsed, contains('get_trek_details'));
      expect(registry.currentTrace.toolCalls, hasLength(2));
      expect(results.first.normalizedResult.trekName, 'annapurna_base_camp');
      expect(results.first.normalizedResult.category, 'info');
      expect(results.first.normalizedResult.information, isNotEmpty);
      expect(
        registry.currentTrace.sourceFiles,
        contains('annapurna_base_camp_trek_data.json'),
      );
    });

    test('rejects invalid trekName safely', () {
      final result = registry.execute(
        ToolCall(
          name: 'get_trek_details',
          arguments: {'trek_name': 'unknown_trek', 'category': 'info'},
        ),
      );

      expect(result.success, false);
      expect(result.payload['error'], contains('Invalid trek_name'));
      expect(result.normalizedResult.trekName, 'unknown_trek');
      expect(result.normalizedResult.category, 'info');
      expect(
        result.normalizedResult.information.single,
        contains('Invalid trek_name'),
      );
    });

    test('detects malformed tool calls separately from final answers', () {
      final malformed = registry.parseToolCallsDetailed(
        'I will call tool_calls get_trek_details for annapurna_base_camp',
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

    test('normalizes every trek category into one ToolResult shape', () {
      for (final category in ToolResult.supportedTrekCategories) {
        final result = registry.execute(
          ToolCall(
            name: 'get_trek_details',
            arguments: {
              'trek_name': 'annapurna_base_camp',
              'category': category,
            },
          ),
        );

        expect(result.success, true, reason: category);
        expect(result.normalizedResult.trekName, 'annapurna_base_camp');
        expect(result.normalizedResult.category, category);
        expect(result.normalizedResult.information, isNotEmpty);
      }
    });

    test('builds deterministic Pass 2 context without raw JSON', () {
      final result = registry.execute(
        ToolCall(
          name: 'get_trek_details',
          arguments: {'trek_name': 'annapurna_base_camp', 'category': 'route'},
        ),
      );

      final prompt = ToolResultPromptBuilder.build(
        question: 'What is the route?',
        result: result.normalizedResult,
      );

      expect(
        prompt,
        startsWith(
          'Trek:\n'
          'annapurna_base_camp\n\n'
          'Question:\n'
          'What is the route?\n\n'
          'Category:\n'
          'route\n\n'
          'Information:\n'
          '- ',
        ),
      );
      expect(prompt, contains('\n\nAdditional Information:\n- '));
      expect(prompt, isNot(contains('{')));
      expect(prompt, isNot(contains('"information"')));
      expect(prompt, isNot(contains('additional_information')));
    });
  });
}
