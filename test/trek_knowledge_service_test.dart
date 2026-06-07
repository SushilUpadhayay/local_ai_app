import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_app/services/trek_knowledge_service.dart';

void main() {
  // Initialize Flutter binding for test environment
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrekKnowledgeService Tests', () {
    late TrekKnowledgeService service;

    setUp(() async {
      service = TrekKnowledgeService();
      await service.initialize();
    });

    test('Loads treks successfully', () {
      expect(service.trekData.length, greaterThanOrEqualTo(3));
      expect(service.trekData.containsKey('annapurna_base_camp'), true);
      expect(service.trekData.containsKey('everest_base_camp'), true);
      expect(service.trekData.containsKey('langtang_valley'), true);
    });

    test('Preprocesses synonyms correctly', () {
      expect(service.preprocessQuery('Where is the closest hospital on the EBC trek?'), contains('health post'));
      expect(service.preprocessQuery('What stay options are there?'), contains('lodge'));
      expect(service.preprocessQuery('Is there a hotel in Ghorepani?'), contains('tea house'));
      expect(service.preprocessQuery('Which mountain is visible from Poon Hill?'), contains('peak'));
      expect(service.preprocessQuery('What are the dangers of altitude sickness?'), contains('risk'));
    });

    test('Detects exact and alias trek matches', () {
      final matchABC = service.detectIntent('Tell me about ABC');
      expect(matchABC, isNotNull);
      expect(matchABC?['trekId'], 'annapurna_base_camp');
      expect(matchABC?['tool'], 'get_trek_info');

      final matchEBC = service.detectIntent('Show me EBC route');
      expect(matchEBC, isNotNull);
      expect(matchEBC?['trekId'], 'everest_base_camp');
      expect(matchEBC?['tool'], 'get_route_info');
    });

    test('Handles ambiguity for overlapping aliases', () {
      final ambiguousResult = service.detectIntent('Tell me about base camp');
      expect(ambiguousResult, isNotNull);
      expect(ambiguousResult?['ambiguous'], true);
      expect(ambiguousResult?['matches'], containsAll(['annapurna_base_camp', 'everest_base_camp']));
    });

    test('Handles multiple trek detection with compare intent', () {
      final compareResult = service.detectIntent('Compare ABC and EBC');
      expect(compareResult, isNotNull);
      expect(compareResult?['tool'], 'compare_treks');
      expect(compareResult?['trekIds'], containsAll(['annapurna_base_camp', 'everest_base_camp']));
    });

    test('Reuses trek context memory for follow-up questions', () {
      final followUpResult = service.detectIntent('How difficult is it?', lastTrekId: 'annapurna_base_camp');
      expect(followUpResult, isNotNull);
      expect(followUpResult?['trekId'], 'annapurna_base_camp');
      expect(followUpResult?['tool'], 'get_trek_info');
      expect(followUpResult?['confidence'], greaterThanOrEqualTo(0.5));
    });

    test('Handles missing trek fallback', () {
      final fallbackResult = service.detectIntent('What is the itinerary?');
      expect(fallbackResult, isNotNull);
      expect(fallbackResult?['fallback'], 'trek_missing');
      expect(fallbackResult?['tool'], 'get_route_info');
    });

    test('Handles unclear intent fallback', () {
      final fallbackResult = service.detectIntent('Everest');
      expect(fallbackResult, isNotNull);
      expect(fallbackResult?['fallback'], 'intent_unclear');
      expect(fallbackResult?['trekId'], 'everest_base_camp');
    });

    test('Tool outputs follow standardized structure', () {
      final info = service.get_trek_info('annapurna_base_camp');
      expect(info['success'], true);
      expect(info['tool'], 'get_trek_info');
      expect(info['trekId'], 'annapurna_base_camp');
      expect(info['source_file'], 'annapurna_base_camp_trek_data.json');
      expect(info['data'], isNotEmpty);
    });

    test('Caching avoids repeated evaluations', () {
      final initialInfo = service.get_route_info('langtang_valley');
      final cachedInfo = service.get_route_info('langtang_valley');
      expect(cachedInfo, same(initialInfo));
    });
  });
}
