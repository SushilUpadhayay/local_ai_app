// ignore_for_file: non_constant_identifier_names
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/trek_data.dart';

class TrekKnowledgeService {
  final Map<String, TrekData> _trekData = {};
  final Map<String, String> _sourceFiles = {};
  final Map<String, dynamic> _toolCache = {};
  bool _isInitialized = false;

  Map<String, TrekData> get trekData => _trekData;
  List<String> get availableTrekNames => _trekData.keys.toList(growable: false);
  bool isValidTrekName(String trekName) => _trekData.containsKey(trekName);

  // Known asset paths for all trek JSON files.
  // Add new treks here when you add a new JSON file to trek_info/.
  static const List<String> _trekAssetPaths = [
    'trek_info/annapurna_base_camp_trek_data.json',
    'trek_info/everest_base_camp_trek_data.json',
    'trek_info/langtang_valley_base_trek_data.json',
  ];

  // 1. Startup Asset Loading & Validation
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      for (final assetPath in _trekAssetPaths) {
        await _loadAsset(assetPath);
      }
      debugPrint(
        '[TrekKnowledgeService] Load complete. Treks in memory: ${_trekData.keys.join(', ')}',
      );
      _isInitialized = true;
    } catch (e) {
      debugPrint('[TrekKnowledgeService] Initialization failed: $e');
    }
  }

  Future<void> _loadAsset(String assetPath) async {
    try {
      final content = await rootBundle.loadString(assetPath);
      final data = jsonDecode(content) as Map<String, dynamic>;
      final filename = assetPath.split('/').last;

      // Validate required fields
      final id = data['id'] as String?;
      final aliases = data['aliases'] as List<dynamic>?;
      final overview = data['overview'];
      final details = data['details'];

      if (id == null ||
          aliases == null ||
          overview == null ||
          details == null) {
        debugPrint(
          '[TrekKnowledgeService] WARNING: Skipping $filename — missing required fields (id, aliases, overview, details).',
        );
        return;
      }

      _trekData[id] = TrekData.fromJson(data);
      _sourceFiles[id] = filename;
      debugPrint(
        '[TrekKnowledgeService] Loaded trek "$id" from $filename  aliases=${aliases.join(', ')}',
      );
    } catch (e) {
      debugPrint(
        '[TrekKnowledgeService] Failed to load asset "$assetPath": $e',
      );
    }
  }

  // 2. Query Preprocessing & Synonym Mapping
  String preprocessQuery(String query) {
    var q = query.toLowerCase().trim();
    // Map synonyms
    q = q.replaceAll(RegExp(r'\bhospitals?\b'), 'health post');
    q = q.replaceAll(RegExp(r'\bstays?\b'), 'lodge');
    q = q.replaceAll(RegExp(r'\bhotels?\b'), 'tea house');
    q = q.replaceAll(RegExp(r'\bmountains?\b'), 'peak');
    q = q.replaceAll(RegExp(r'\bdangers?\b'), 'risk');
    return q;
  }



  Map<String, String>? _findMatchingFaq(
    String trekName,
    String preprocessedQuery,
  ) {
    final trek = _trekData[trekName];
    if (trek == null) return null;
    final faqs = trek.faq;
    if (faqs.isEmpty) return null;

    final queryWords = _tokenize(preprocessedQuery);
    if (queryWords.isEmpty) return null;

    Map<String, String>? bestFaq;
    double bestScore = 0.0;

    for (final faq in faqs) {
      final q = (faq['question'] ?? '').toLowerCase();
      final qWords = _tokenize(q);
      int intersection = 0;
      for (final qw in queryWords) {
        if (qWords.contains(qw)) intersection++;
      }
      final union = (queryWords.length + qWords.length - intersection);
      final score = union > 0 ? intersection / union : 0.0;
      if (score > bestScore) {
        bestScore = score;
        bestFaq = faq;
      }
    }

    if (bestScore < 0.1) {
      int bestOverlapLength = 0;
      for (final faq in faqs) {
        final q = (faq['question'] ?? '').toLowerCase();
        final words1 = preprocessedQuery.split(RegExp(r'\s+'));
        final words2 = q.split(RegExp(r'\s+'));
        int common = 0;
        for (final w in words1) {
          if (w.length > 2 && words2.contains(w)) common++;
        }
        if (common > bestOverlapLength) {
          bestOverlapLength = common;
          bestFaq = faq;
          bestScore = common > 0 ? 0.5 : 0.0;
        }
      }
    }

    if (bestFaq != null && bestScore > 0.15) {
      return {
        'question': bestFaq['question'] ?? '',
        'answer': bestFaq['answer'] ?? '',
      };
    }
    return null;
  }

  List<String> _tokenize(String text) {
    final stopWords = {
      'is',
      'the',
      'a',
      'of',
      'to',
      'on',
      'in',
      'for',
      'do',
      'i',
      'can',
      'what',
      'how',
      'are',
      'about',
      'with',
      'at',
      'from',
      'trek',
      'abcs',
      'ebcs',
      'it',
      'its',
      'you',
      'your',
      'me',
      'my',
      'we',
    };
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !stopWords.contains(w))
        .toList();
  }

  Map<String, dynamic> _executeWithCache(
    String toolName,
    String cacheKey,
    Map<String, dynamic> Function() toolExecution,
  ) {
    final key = '${toolName}_$cacheKey';
    if (_toolCache.containsKey(key)) return _toolCache[key];
    final result = toolExecution();
    _toolCache[key] = result;
    return result;
  }

  Map<String, dynamic> _standardResponse({
    required bool success,
    required String tool,
    required String trekName,
    required Map<String, dynamic> data,
    String? error,
  }) {
    final response = <String, dynamic>{
      'success': success,
      'tool': tool,
      'trek_name': trekName,
      'source_file': _sourceFiles[trekName] ?? 'unknown',
      'data': data,
    };
    if (error != null) response['error'] = error;
    return response;
  }



  Map<String, dynamic> get_trek_overview(String trekName) {
    return _executeWithCache('get_trek_overview', trekName, () {
      final trek = _trekData[trekName];
      if (trek == null)
        return _standardResponse(
          success: false,
          tool: 'get_trek_overview',
          trekName: trekName,
          error: 'Trek not found',
          data: {},
        );
      return _standardResponse(
        success: true,
        tool: 'get_trek_overview',
        trekName: trekName,
        data: Map<String, dynamic>.from(trek.overview),
      );
    });
  }

  Map<String, dynamic> get_trek_details(String trekName, String categoryVal) {
    final cacheKey = '${trekName}_$categoryVal';
    return _executeWithCache('get_trek_details', cacheKey, () {
      final trek = _trekData[trekName];
      if (trek == null)
        return _standardResponse(
          success: false,
          tool: 'get_trek_details',
          trekName: trekName,
          error: 'Trek not found',
          data: {},
        );

      String effectiveCategory = categoryVal;
      if (effectiveCategory == 'itinerary') effectiveCategory = 'route';

      final category = TrekCategory.fromString(effectiveCategory);
      if (category == null)
        return _standardResponse(
          success: false,
          tool: 'get_trek_details',
          trekName: trekName,
          error: 'Invalid category: $categoryVal',
          data: {},
        );
      final detailData = trek.details[category];
      if (detailData == null)
        return _standardResponse(
          success: false,
          tool: 'get_trek_details',
          trekName: trekName,
          error: 'Category details not found: ${category.name}',
          data: {},
        );

      if (categoryVal == 'itinerary' && detailData.containsKey('itinerary')) {
        return _standardResponse(
          success: true,
          tool: 'get_trek_details',
          trekName: trekName,
          data: {'itinerary': detailData['itinerary']},
        );
      }
      return _standardResponse(
        success: true,
        tool: 'get_trek_details',
        trekName: trekName,
        data: Map<String, dynamic>.from(detailData),
      );
    });
  }

  Map<String, dynamic> get_trek_faq(String trekName, String question) {
    final cleanQuery = preprocessQuery(question);
    final faqResult = _findMatchingFaq(trekName, cleanQuery);
    if (faqResult == null)
      return _standardResponse(
        success: false,
        tool: 'get_trek_faq',
        trekName: trekName,
        error: 'No matching FAQ answer found.',
        data: {},
      );
    return _standardResponse(
      success: true,
      tool: 'get_trek_faq',
      trekName: trekName,
      data: faqResult,
    );
  }



  Map<String, dynamic> list_available_treks() {
    return _executeWithCache('list_available_treks', 'all', () {
      final List<Map<String, dynamic>> treks = [];
      _trekData.forEach((id, trek) {
        final overview = trek.overview;
        treks.add({
          'trek_name': id,
          'name': overview['trek_name'],
          'difficulty': overview['difficulty_level'],
          'duration_days': overview['trek_duration']?['standard_days'],
          'max_altitude': overview['maximum_altitude'],
          'overview': overview['overview'],
        });
      });
      return _standardResponse(
        success: true,
        tool: 'list_available_treks',
        trekName: 'all',
        data: {'treks': treks},
      );
    });
  }
}
