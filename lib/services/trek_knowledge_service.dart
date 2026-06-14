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
  List<String> get availableTrekNames =>
      _trekData.keys.toList(growable: false);
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

  // 3. Local Intent Classification with Confidence Scoring and Ambiguity Handling
  Map<String, dynamic>? detectIntent(String query, {String? lastTrekName}) {
    final preprocessed = preprocessQuery(query);

    // Trek Matching
    final matchedTreks = <String>{};
    _trekData.forEach((id, data) {
      final aliases = data.aliases;
      for (final alias in aliases) {
        final aliasLower = alias.toLowerCase().trim();
        bool matched;
        if (aliasLower.contains(' ')) {
          matched = preprocessed.contains(aliasLower);
        } else {
          final pattern =
              '(?:^|[^a-z0-9])${RegExp.escape(aliasLower)}(?:[^a-z0-9]|\$)';
          matched = RegExp(
            pattern,
            caseSensitive: false,
          ).hasMatch(preprocessed);
        }
        if (matched) {
          matchedTreks.add(id);
          break;
        }
      }
    });

    if (matchedTreks.isEmpty && preprocessed.contains('base camp')) {
      _trekData.forEach((id, data) {
        final overview = data.overview;
        final name = (overview['trek_name'] as String? ?? '').toLowerCase();
        final aliases = data.aliases;
        if (name.contains('base camp') ||
            aliases.any((alias) => alias.toLowerCase().contains('base camp'))) {
          matchedTreks.add(id);
        }
      });
    }

    debugPrint(
      '[TrekKnowledgeService] detectIntent: query="$query"'
      '  preprocessed="$preprocessed"  matched=$matchedTreks  ctx=$lastTrekName',
    );

    // Context fallback
    String? matchedTrekName;
    bool isContextUsed = false;
    if (matchedTreks.isEmpty &&
        lastTrekName != null &&
        _trekData.containsKey(lastTrekName)) {
      matchedTrekName = lastTrekName;
      isContextUsed = true;
    } else if (matchedTreks.length == 1) {
      matchedTrekName = matchedTreks.first;
    }

    // Ambiguity / Comparison
    if (matchedTreks.length > 1) {
      const compareKeywords = {
        'compare',
        'comparison',
        'difference',
        'versus',
        'vs',
        'which',
        'harder',
        'easier',
        'longer',
        'shorter',
        'better',
      };
      final isCompare = compareKeywords.any((kw) => preprocessed.contains(kw));

      if (isCompare) {
        return {
          'tool': 'compare_treks',
          'trek_names': matchedTreks.toList(),
          'confidence': 0.95,
        };
      }
      return {
        'ambiguous': true,
        'matches': matchedTreks.toList(),
        'confidence': 0.90,
      };
    }

    // Intent scoring
    final intentScores = <String, int>{};
    intentScores['get_route_info'] = _countKeywordMatches(preprocessed, ['route', 'itinerary', 'day', 'days', 'schedule', 'path', 'distance', 'walk', 'walking', 'hour', 'hours', 'elevation', 'map', 'how long']);
    intentScores['get_landmarks'] = _countKeywordMatches(preprocessed, ['landmark', 'peak', 'peaks', 'river', 'lake', 'viewpoint', 'forest', 'culture', 'cultural', 'monastery', 'temple', 'shrine', 'visible', 'see']);
    intentScores['get_villages'] = _countKeywordMatches(preprocessed, ['village', 'settlement', 'lodge', 'lodging', 'tea house', 'facility', 'room', 'accommodation', 'stay', 'sleep', 'night']);
    intentScores['get_health_posts'] = _countKeywordMatches(preprocessed, ['health post', 'medical', 'doctor', 'clinic', 'first aid', 'hospital']);
    intentScores['get_emergency_info'] = _countKeywordMatches(preprocessed, ['emergency', 'risk', 'safety', 'accident', 'altitude', 'sickness', 'ams', 'hape', 'hace', 'symptom', 'prevent', 'rescue', 'helicopter', 'evacuation']);
    intentScores['get_transport_info'] = _countKeywordMatches(preprocessed, ['transport', 'bus', 'jeep', 'flight', 'reach', 'drive', 'travel', 'starting point', 'access', 'road', 'how to get']);
    intentScores['get_trek_info'] = _countKeywordMatches(preprocessed, ['info', 'about', 'overview', 'tell', 'explain', 'describe', 'what is', 'what are', 'difficulty', 'difficult', 'duration', 'season', 'permit', 'acap', 'tims', 'fee', 'cost', 'general']);
    intentScores['list_available_treks'] = _countKeywordMatches(preprocessed, ['list treks', 'available treks', 'what treks', 'show treks', 'trek options', 'all treks', 'list of treks']);

    var bestTool = 'get_trek_info';
    var maxScore = 0;
    intentScores.forEach((tool, score) {
      if (score > maxScore) {
        maxScore = score;
        bestTool = tool;
      }
    });

    if (bestTool == 'list_available_treks' && maxScore > 0) {
      return {
        'tool': 'list_available_treks',
        'trek_name': 'all',
        'confidence': 0.95,
      };
    }

    // No trek found
    if (matchedTrekName == null && matchedTreks.isEmpty) {
      if (maxScore > 0 && bestTool != 'list_available_treks') {
        final categoryMapping = {
          'get_route_info': 'route',
          'get_landmarks': 'landmarks',
          'get_villages': 'villages',
          'get_health_posts': 'hospitals',
          'get_emergency_info': 'emergency',
          'get_transport_info': 'transport',
        };
        final finalTool = categoryMapping.containsKey(bestTool) ? 'get_trek_details' : 'get_trek_overview';
        return {
          'fallback': 'trek_missing',
          'tool': finalTool,
          'confidence': 0.80,
          if (categoryMapping.containsKey(bestTool)) 'category': categoryMapping[bestTool],
        };
      }
      return null;
    }

    // Trek resolved
    final trekName = matchedTrekName!;
    final faqMatchResult = _findMatchingFaq(trekName, preprocessed);
    final categoryMapping = {
      'get_route_info': 'route',
      'get_landmarks': 'landmarks',
      'get_villages': 'villages',
      'get_health_posts': 'hospitals',
      'get_emergency_info': 'emergency',
      'get_transport_info': 'transport',
    };

    String finalTool;
    String? finalCategory;
    double confidence;

    if (maxScore > 0) {
      if (categoryMapping.containsKey(bestTool)) {
        finalTool = 'get_trek_details';
        finalCategory = categoryMapping[bestTool];
      } else if (bestTool == 'get_trek_info') {
        finalTool = 'get_trek_overview';
      } else {
        finalTool = bestTool;
      }
      confidence = 0.55 + (0.43 * (maxScore / (preprocessed.split(RegExp(r'\s+')).length + 1)));
      confidence = confidence.clamp(0.55, 0.98);
    } else if (faqMatchResult != null) {
      finalTool = 'get_trek_faq';
      confidence = 0.90;
    } else if (!isContextUsed) {
      return {
        'fallback': 'intent_unclear',
        'trek_name': trekName,
        'confidence': 0.75,
      };
    } else {
      return null;
    }

    if (confidence < 0.5) return null;

    debugPrint(
      '[TrekKnowledgeService] → tool=$finalTool trekName=$trekName confidence=${confidence.toStringAsFixed(2)}',
    );

    return {
      'tool': finalTool,
      'trek_name': trekName,
      'confidence': double.parse(confidence.toStringAsFixed(2)),
      'category': ?finalCategory,
      if (finalTool == 'get_trek_faq') 'raw_question': query,
    };
  }

  int _countKeywordMatches(String text, List<String> keywords) {
    int count = 0;
    for (final kw in keywords) {
      if (text.contains(kw)) {
        count++;
      }
    }
    return count;
  }

  Map<String, String>? _findMatchingFaq(String trekName, String preprocessedQuery) {
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
    final stopWords = {'is', 'the', 'a', 'of', 'to', 'on', 'in', 'for', 'do', 'i', 'can', 'what', 'how', 'are', 'about', 'with', 'at', 'from', 'trek', 'abcs', 'ebcs', 'it', 'its', 'you', 'your', 'me', 'my', 'we'};
    return text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').split(RegExp(r'\s+')).where((w) => w.isNotEmpty && !stopWords.contains(w)).toList();
  }

  Map<String, dynamic> _executeWithCache(String toolName, String cacheKey, Map<String, dynamic> Function() toolExecution) {
    final key = '${toolName}_$cacheKey';
    if (_toolCache.containsKey(key)) return _toolCache[key];
    final result = toolExecution();
    _toolCache[key] = result;
    return result;
  }

  Map<String, dynamic> _standardResponse({required bool success, required String tool, required String trekName, required Map<String, dynamic> data, String? error}) {
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

  // 5. Standardized 6 Generic Tools Implementation
  Map<String, dynamic> search_trek(String query) {
    final cleanQuery = query.toLowerCase().trim();
    return _executeWithCache('search_trek', cleanQuery, () {
      final List<Map<String, dynamic>> matches = [];
      _trekData.forEach((id, trek) {
        final overview = trek.overview;
        final name = (overview['trek_name'] as String? ?? '').toLowerCase();
        final aliases = trek.aliases.map((a) => a.toLowerCase()).toList();
        bool isMatch = id.contains(cleanQuery) || name.contains(cleanQuery) || aliases.any((a) => a.contains(cleanQuery));
        if (isMatch || cleanQuery.isEmpty) {
          matches.add({'trek_name': id, 'name': overview['trek_name'], 'overview': overview['overview'], 'difficulty': overview['difficulty_level'], 'duration': overview['trek_duration']?['standard_days'], 'max_altitude': overview['maximum_altitude']});
        }
      });
      return _standardResponse(success: true, tool: 'search_trek', trekName: matches.isNotEmpty ? matches.first['trek_name'] : 'none', data: {'matches': matches});
    });
  }

  Map<String, dynamic> get_trek_overview(String trekName) {
    return _executeWithCache('get_trek_overview', trekName, () {
      final trek = _trekData[trekName];
      if (trek == null) return _standardResponse(success: false, tool: 'get_trek_overview', trekName: trekName, error: 'Trek not found', data: {});
      return _standardResponse(success: true, tool: 'get_trek_overview', trekName: trekName, data: Map<String, dynamic>.from(trek.overview));
    });
  }

  Map<String, dynamic> get_trek_details(String trekName, String categoryVal) {
    final cacheKey = '${trekName}_$categoryVal';
    return _executeWithCache('get_trek_details', cacheKey, () {
      final trek = _trekData[trekName];
      if (trek == null) return _standardResponse(success: false, tool: 'get_trek_details', trekName: trekName, error: 'Trek not found', data: {});
      final category = TrekCategory.fromString(categoryVal);
      if (category == null) return _standardResponse(success: false, tool: 'get_trek_details', trekName: trekName, error: 'Invalid category: $categoryVal', data: {});
      final detailData = trek.details[category];
      if (detailData == null) return _standardResponse(success: false, tool: 'get_trek_details', trekName: trekName, error: 'Category details not found: ${category.name}', data: {});
      return _standardResponse(success: true, tool: 'get_trek_details', trekName: trekName, data: Map<String, dynamic>.from(detailData));
    });
  }

  Map<String, dynamic> get_trek_faq(String trekName, String question) {
    final cleanQuery = preprocessQuery(question);
    final faqResult = _findMatchingFaq(trekName, cleanQuery);
    if (faqResult == null) return _standardResponse(success: false, tool: 'get_trek_faq', trekName: trekName, error: 'No matching FAQ answer found.', data: {});
    return _standardResponse(success: true, tool: 'get_trek_faq', trekName: trekName, data: faqResult);
  }

  Map<String, dynamic> compare_treks(List<String> trekNames) {
    final cacheKey = trekNames.join('_');
    return _executeWithCache('compare_treks', cacheKey, () {
      final List<Map<String, dynamic>> comparisons = [];
      for (final name in trekNames) {
        final trek = _trekData[name];
        if (trek != null) {
          final overview = trek.overview;
          comparisons.add({'trek_name': name, 'name': overview['trek_name'], 'overview': overview['overview'], 'difficulty': overview['difficulty_level'], 'duration': overview['trek_duration']?['standard_days'], 'max_altitude': overview['maximum_altitude'], 'total_distance': overview['total_distance']});
        }
      }
      return _standardResponse(success: true, tool: 'compare_treks', trekName: comparisons.isNotEmpty ? comparisons.first['trek_name'] : 'none', data: {'comparisons': comparisons});
    });
  }

  Map<String, dynamic> list_available_treks() {
    return _executeWithCache('list_available_treks', 'all', () {
      final List<Map<String, dynamic>> treks = [];
      _trekData.forEach((id, trek) {
        final overview = trek.overview;
        treks.add({'trek_name': id, 'name': overview['trek_name'], 'difficulty': overview['difficulty_level'], 'duration_days': overview['trek_duration']?['standard_days'], 'max_altitude': overview['maximum_altitude'], 'overview': overview['overview']});
      });
      return _standardResponse(success: true, tool: 'list_available_treks', trekName: 'all', data: {'treks': treks});
    });
  }

  Map<String, dynamic> get_trek_info(String trekName) => get_trek_overview(trekName);
  Map<String, dynamic> get_route_info(String trekName) => get_trek_details(trekName, 'route');
  Map<String, dynamic> get_landmarks(String trekName) => get_trek_details(trekName, 'landmarks');
  Map<String, dynamic> get_villages(String trekName) => get_trek_details(trekName, 'villages');
  Map<String, dynamic> get_health_posts(String trekName) {
    final detailsRes = get_trek_details(trekName, 'hospitals');
    if (!detailsRes['success']) return detailsRes;
    final emergencyRes = get_trek_details(trekName, 'emergency');
    final detailMap = detailsRes['data'] as Map<String, dynamic>;
    final emergencyMap = (emergencyRes['success'] ? emergencyRes['data'] : const {}) as Map<String, dynamic>;
    return _standardResponse(success: true, tool: 'get_health_posts', trekName: trekName, data: {'health_posts': detailMap['health_posts'], 'medical_centers': detailMap['medical_centers'], 'rescue_points': emergencyMap['rescue_points'], 'helicopter_evacuation_locations': emergencyMap['helicopter_evacuation_locations']});
  }
  Map<String, dynamic> get_emergency_info(String trekName) => get_trek_details(trekName, 'emergency');
  Map<String, dynamic> get_transport_info(String trekName) => get_trek_details(trekName, 'transport');
  Map<String, dynamic> get_faq_answer(String trekName, String question) => get_trek_faq(trekName, question);

  Map<String, dynamic> find_nearest_location(double lat, double lon) => {'success': true, 'tool': 'find_nearest_location', 'trek_name': 'none', 'data': {'latitude': lat, 'longitude': lon, 'note': 'GPS services are offline.', 'nearest_points': []}};
  Map<String, dynamic> find_nearest_health_post(double lat, double lon) => {'success': true, 'tool': 'find_nearest_health_post', 'trek_name': 'none', 'data': {'latitude': lat, 'longitude': lon, 'note': 'GPS services are offline.', 'nearest_health_posts': []}};
}
