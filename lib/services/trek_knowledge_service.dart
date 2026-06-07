// ignore_for_file: non_constant_identifier_names
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TrekKnowledgeService {
  final Map<String, Map<String, dynamic>> _trekData = {};
  final Map<String, String> _sourceFiles = {};
  final Map<String, dynamic> _toolCache = {};
  bool _isInitialized = false;

  Map<String, Map<String, dynamic>> get trekData => _trekData;

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
      debugPrint('[TrekKnowledgeService] Load complete. Treks in memory: ${_trekData.keys.join(', ')}');
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
      final basicInfo = data['basic_trek_information'];
      final routeInfo = data['route_information'];

      if (id == null || aliases == null || basicInfo == null || routeInfo == null) {
        debugPrint('[TrekKnowledgeService] WARNING: Skipping $filename — missing required fields (id, aliases, basic_trek_information, route_information).');
        return;
      }

      _trekData[id] = data;
      _sourceFiles[id] = filename;
      debugPrint('[TrekKnowledgeService] Loaded trek "$id" from $filename  aliases=${aliases.join(', ')}');
    } catch (e) {
      debugPrint('[TrekKnowledgeService] Failed to load asset "$assetPath": $e');
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
  Map<String, dynamic>? detectIntent(String query, {String? lastTrekId}) {
    final preprocessed = preprocessQuery(query);

    // Trek Matching 
    // Strategy: for each alias, check if it appears as a whole word/phrase in
    // the preprocessed query. Multi-word aliases use simple containment; single
    // words use a character-boundary check so "abc" doesn't match "abcdef".
    final matchedTreks = <String>{};
    _trekData.forEach((id, data) {
      final aliases = List<String>.from(data['aliases'] ?? []);
      for (final alias in aliases) {
        final aliasLower = alias.toLowerCase().trim();
        bool matched;
        if (aliasLower.contains(' ')) {
          // Multi-word phrase → simple substring containment is sufficient
          matched = preprocessed.contains(aliasLower);
        } else {
          // Single word → require non-letter boundary on both sides so that
          // "abc" in "tell me about abc" matches but "a" in "annapurna" doesn't
          final pattern = '(?:^|[^a-z0-9])${RegExp.escape(aliasLower)}(?:[^a-z0-9]|\$)';
          matched = RegExp(pattern, caseSensitive: false).hasMatch(preprocessed);
        }
        if (matched) {
          matchedTreks.add(id);
          break; // found for this trek → move to next
        }
      }
    });

    debugPrint('[TrekKnowledgeService] detectIntent: query="$query"'
        '  preprocessed="$preprocessed"  matched=$matchedTreks  ctx=$lastTrekId');

    // Context fallback 
    String? matchedTrekId;
    bool isContextUsed = false;
    if (matchedTreks.isEmpty && lastTrekId != null && _trekData.containsKey(lastTrekId)) {
      matchedTrekId = lastTrekId;
      isContextUsed = true;
    } else if (matchedTreks.length == 1) {
      matchedTrekId = matchedTreks.first;
    }

    // Ambiguity / Comparison 
    if (matchedTreks.length > 1) {
      const compareKeywords = {
        'compare', 'comparison', 'difference', 'versus', 'vs',
        'which', 'harder', 'easier', 'longer', 'shorter', 'better'
      };
      final isCompare = compareKeywords.any((kw) => preprocessed.contains(kw));

      if (isCompare) {
        return {'tool': 'compare_treks', 'trekIds': matchedTreks.toList(), 'confidence': 0.95};
      }
      return {'ambiguous': true, 'matches': matchedTreks.toList(), 'confidence': 0.90};
    }

    // Intent scoring 
    final intentScores = <String, int>{};

    intentScores['get_route_info'] = _countKeywordMatches(preprocessed, [
      'route', 'itinerary', 'day', 'days', 'schedule', 'path', 'distance',
      'walk', 'walking', 'hour', 'hours', 'elevation', 'map', 'how long',
    ]);

    intentScores['get_landmarks'] = _countKeywordMatches(preprocessed, [
      'landmark', 'peak', 'peaks', 'river', 'lake', 'viewpoint', 'forest',
      'culture', 'cultural', 'monastery', 'temple', 'shrine', 'visible', 'see',
    ]);

    intentScores['get_villages'] = _countKeywordMatches(preprocessed, [
      'village', 'settlement', 'lodge', 'lodging', 'tea house', 'facility',
      'room', 'accommodation', 'stay', 'sleep', 'night',
    ]);

    intentScores['get_health_posts'] = _countKeywordMatches(preprocessed, [
      'health post', 'medical', 'doctor', 'clinic', 'first aid', 'hospital',
    ]);

    intentScores['get_emergency_info'] = _countKeywordMatches(preprocessed, [
      'emergency', 'risk', 'safety', 'accident', 'altitude', 'sickness',
      'ams', 'hape', 'hace', 'symptom', 'prevent', 'rescue', 'helicopter', 'evacuation',
    ]);

    intentScores['get_transport_info'] = _countKeywordMatches(preprocessed, [
      'transport', 'bus', 'jeep', 'flight', 'reach', 'drive', 'travel',
      'starting point', 'access', 'road', 'how to get',
    ]);

    // get_trek_info covers general curiosity: "tell me about", "what is", etc.
    intentScores['get_trek_info'] = _countKeywordMatches(preprocessed, [
      'info', 'about', 'overview', 'tell', 'explain', 'describe',
      'what is', 'what are', 'difficulty', 'difficult', 'duration',
      'season', 'permit', 'acap', 'tims', 'fee', 'cost', 'general',
    ]);

    intentScores['list_available_treks'] = _countKeywordMatches(preprocessed, [
      'list treks', 'available treks', 'what treks', 'show treks',
      'trek options', 'all treks', 'list of treks',
    ]);

    var bestTool = 'get_trek_info';
    var maxScore = 0;
    intentScores.forEach((tool, score) {
      if (score > maxScore) {
        maxScore = score;
        bestTool = tool;
      }
    });

    // list_available_treks doesn't need a trek matched
    if (bestTool == 'list_available_treks' && maxScore > 0) {
      return {'tool': 'list_available_treks', 'trekId': 'all', 'confidence': 0.95};
    }

    // No trek found 
    if (matchedTrekId == null && matchedTreks.isEmpty) {
      if (maxScore > 0 && bestTool != 'list_available_treks') {
        // Intent keywords present but no trek name → suggest treks
        return {'fallback': 'trek_missing', 'tool': bestTool, 'confidence': 0.80};
      }
      return null; // pure general chat
    }

    // Trek resolved
    final trekId = matchedTrekId!;

    // FAQ overlap check
    final faqMatchResult = _findMatchingFaq(trekId, preprocessed);

    String finalTool;
    double confidence;

    if (maxScore > 0) {
      finalTool = bestTool;
      confidence = 0.55 + (0.43 * (maxScore / (preprocessed.split(RegExp(r'\s+')).length + 1)));
      confidence = confidence.clamp(0.55, 0.98);
    } else if (faqMatchResult != null) {
      finalTool = 'get_faq_answer';
      confidence = 0.90;
    } else if (!isContextUsed) {
      // Trek name explicitly mentioned but no specific intent keyword →
      // treat as a general overview request ("Tell me about ABC")
      finalTool = 'get_trek_info';
      confidence = 0.75;
    } else {
      // Context-only match with no intent → let general chat handle it
      return null;
    }

    if (confidence < 0.5) return null;

    debugPrint('[TrekKnowledgeService] → tool=$finalTool trekId=$trekId confidence=${confidence.toStringAsFixed(2)}');

    return {
      'tool': finalTool,
      'trekId': trekId,
      'confidence': double.parse(confidence.toStringAsFixed(2)),
      if (finalTool == 'get_faq_answer') 'raw_question': query,
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

  Map<String, String>? _findMatchingFaq(String trekId, String preprocessedQuery) {
    final trek = _trekData[trekId];
    if (trek == null) return null;
    final faqs = trek['facts_frequently_asked_by_trekkers'] as List<dynamic>?;
    if (faqs == null || faqs.isEmpty) return null;

    final queryWords = _tokenize(preprocessedQuery);
    if (queryWords.isEmpty) return null;

    dynamic bestFaq;
    double bestScore = 0.0;

    for (final faq in faqs) {
      final q = (faq['question'] as String? ?? '').toLowerCase();
      final qWords = _tokenize(q);
      
      int intersection = 0;
      for (final qw in queryWords) {
        if (qWords.contains(qw)) {
          intersection++;
        }
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
        final q = (faq['question'] as String? ?? '').toLowerCase();
        final words1 = preprocessedQuery.split(RegExp(r'\s+'));
        final words2 = q.split(RegExp(r'\s+'));
        int common = 0;
        for (final w in words1) {
          if (w.length > 2 && words2.contains(w)) {
            common++;
          }
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
        'question': bestFaq['question'] as String,
        'answer': bestFaq['answer'] as String,
      };
    }
    return null;
  }

  List<String> _tokenize(String text) {
    final stopWords = {
      'is', 'the', 'a', 'of', 'to', 'on', 'in', 'for', 'do', 'i', 'can', 'what', 'how', 'are', 'about', 'with', 'at', 'from', 'trek', 'abcs', 'ebcs',
      'it', 'its', 'you', 'your', 'me', 'my', 'we'
    };
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !stopWords.contains(w))
        .toList();
  }

  // 4. In-Memory Tool Result Cache Wrapper
  Map<String, dynamic> _executeWithCache(String toolName, String trekId, Map<String, dynamic> Function() toolExecution) {
    final cacheKey = '${toolName}_$trekId';
    if (_toolCache.containsKey(cacheKey)) {
      debugPrint('[TrekKnowledgeService] CACHE HIT: Returning cached result for $cacheKey');
      return _toolCache[cacheKey];
    }
    final result = toolExecution();
    _toolCache[cacheKey] = result;
    return result;
  }

  Map<String, dynamic> _standardResponse({
    required bool success,
    required String tool,
    required String trekId,
    required Map<String, dynamic> data,
    String? error,
  }) {
    final response = <String, dynamic>{
      'success': success,
      'tool': tool,
      'trekId': trekId,
      'source_file': _sourceFiles[trekId] ?? 'unknown',
      'data': data,
    };
    if (error != null) {
      response['error'] = error;
    }
    return response;
  }

  // 5. Standardized MVP Tools Implementation

  Map<String, dynamic> search_trek(String trekName) {
    final cleanName = trekName.toLowerCase().trim();
    return _executeWithCache('search_trek', cleanName, () {
      final List<Map<String, dynamic>> matches = [];
      _trekData.forEach((id, data) {
        final basicInfo = data['basic_trek_information'] ?? {};
        final aliases = List<String>.from(data['aliases'] ?? []);
        bool isMatch = id.contains(cleanName) ||
            (basicInfo['trek_name'] as String? ?? '').toLowerCase().contains(cleanName) ||
            aliases.any((a) => a.contains(cleanName));

        if (isMatch || cleanName.isEmpty) {
          matches.add({
            'trekId': id,
            'name': basicInfo['trek_name'],
            'overview': basicInfo['overview'],
            'difficulty': basicInfo['difficulty_level'],
            'duration': basicInfo['trek_duration']?['standard_days'],
            'max_altitude': basicInfo['maximum_altitude'],
          });
        }
      });

      return _standardResponse(
        success: true,
        tool: 'search_trek',
        trekId: matches.isNotEmpty ? matches.first['trekId'] : 'none',
        data: {'matches': matches},
      );
    });
  }

  Map<String, dynamic> get_trek_info(String trekId) {
    return _executeWithCache('get_trek_info', trekId, () {
      final trek = _trekData[trekId];
      if (trek == null) {
        return _standardResponse(success: false, tool: 'get_trek_info', trekId: trekId, error: 'Trek not found', data: {});
      }
      return _standardResponse(
        success: true,
        tool: 'get_trek_info',
        trekId: trekId,
        data: Map<String, dynamic>.from(trek['basic_trek_information'] ?? {}),
      );
    });
  }

  Map<String, dynamic> get_route_info(String trekId) {
    return _executeWithCache('get_route_info', trekId, () {
      final trek = _trekData[trekId];
      if (trek == null) {
        return _standardResponse(success: false, tool: 'get_route_info', trekId: trekId, error: 'Trek not found', data: {});
      }
      return _standardResponse(
        success: true,
        tool: 'get_route_info',
        trekId: trekId,
        data: Map<String, dynamic>.from(trek['route_information'] ?? {}),
      );
    });
  }

  Map<String, dynamic> get_landmarks(String trekId) {
    return _executeWithCache('get_landmarks', trekId, () {
      final trek = _trekData[trekId];
      if (trek == null) {
        return _standardResponse(success: false, tool: 'get_landmarks', trekId: trekId, error: 'Trek not found', data: {});
      }
      return _standardResponse(
        success: true,
        tool: 'get_landmarks',
        trekId: trekId,
        data: Map<String, dynamic>.from(trek['landmarks_and_attractions'] ?? {}),
      );
    });
  }

  Map<String, dynamic> get_villages(String trekId) {
    return _executeWithCache('get_villages', trekId, () {
      final trek = _trekData[trekId];
      if (trek == null) {
        return _standardResponse(success: false, tool: 'get_villages', trekId: trekId, error: 'Trek not found', data: {});
      }
      return _standardResponse(
        success: true,
        tool: 'get_villages',
        trekId: trekId,
        data: Map<String, dynamic>.from(trek['villages_and_settlements'] ?? {}),
      );
    });
  }

  Map<String, dynamic> get_health_posts(String trekId) {
    return _executeWithCache('get_health_posts', trekId, () {
      final trek = _trekData[trekId];
      if (trek == null) {
        return _standardResponse(success: false, tool: 'get_health_posts', trekId: trekId, error: 'Trek not found', data: {});
      }
      final healthAndEmergency = trek['health_and_emergency_information'] ?? {};
      return _standardResponse(
        success: true,
        tool: 'get_health_posts',
        trekId: trekId,
        data: {
          'health_posts': healthAndEmergency['health_posts'],
          'medical_centers': healthAndEmergency['medical_centers'],
          'rescue_points': healthAndEmergency['rescue_points'],
          'helicopter_evacuation_locations': healthAndEmergency['helicopter_evacuation_locations'],
        },
      );
    });
  }

  Map<String, dynamic> get_emergency_info(String trekId) {
    return _executeWithCache('get_emergency_info', trekId, () {
      final trek = _trekData[trekId];
      if (trek == null) {
        return _standardResponse(success: false, tool: 'get_emergency_info', trekId: trekId, error: 'Trek not found', data: {});
      }
      return _standardResponse(
        success: true,
        tool: 'get_emergency_info',
        trekId: trekId,
        data: Map<String, dynamic>.from(trek['health_and_emergency_information'] ?? {}),
      );
    });
  }

  Map<String, dynamic> get_transport_info(String trekId) {
    return _executeWithCache('get_transport_info', trekId, () {
      final trek = _trekData[trekId];
      if (trek == null) {
        return _standardResponse(success: false, tool: 'get_transport_info', trekId: trekId, error: 'Trek not found', data: {});
      }
      return _standardResponse(
        success: true,
        tool: 'get_transport_info',
        trekId: trekId,
        data: Map<String, dynamic>.from(trek['transportation_information'] ?? {}),
      );
    });
  }

  Map<String, dynamic> get_faq_answer(String trekId, String question) {
    // Avoid double caching on FAQ raw question (might have small text variations)
    // We search FAQ directly, but we standard response caches query inside faq lookup
    final cleanQuery = preprocessQuery(question);
    final faqResult = _findMatchingFaq(trekId, cleanQuery);
    if (faqResult == null) {
      return _standardResponse(
        success: false,
        tool: 'get_faq_answer',
        trekId: trekId,
        error: 'No matching FAQ answer found.',
        data: {},
      );
    }
    return _standardResponse(
      success: true,
      tool: 'get_faq_answer',
      trekId: trekId,
      data: faqResult,
    );
  }

  Map<String, dynamic> list_available_treks() {
    return _executeWithCache('list_available_treks', 'all', () {
      final List<Map<String, dynamic>> treks = [];
      _trekData.forEach((id, data) {
        final basicInfo = data['basic_trek_information'] ?? {};
        treks.add({
          'trekId': id,
          'name': basicInfo['trek_name'],
          'difficulty': basicInfo['difficulty_level'],
          'duration_days': basicInfo['trek_duration']?['standard_days'],
          'max_altitude': basicInfo['maximum_altitude'],
          'overview': basicInfo['overview'],
        });
      });
      return _standardResponse(
        success: true,
        tool: 'list_available_treks',
        trekId: 'all',
        data: {'treks': treks},
      );
    });
  }

  // 6. GPS Future Placeholder Tools
  Map<String, dynamic> find_nearest_location(double lat, double lon) {
    return {
      'success': true,
      'tool': 'find_nearest_location',
      'trekId': 'none',
      'data': {
        'latitude': lat,
        'longitude': lon,
        'note': 'GPS services are offline. Nearest location tracking placeholder triggered.',
        'nearest_points': []
      }
    };
  }

  Map<String, dynamic> find_nearest_health_post(double lat, double lon) {
    return {
      'success': true,
      'tool': 'find_nearest_health_post',
      'trekId': 'none',
      'data': {
        'latitude': lat,
        'longitude': lon,
        'note': 'GPS services are offline. Nearest medical facility tracking placeholder triggered.',
        'nearest_health_posts': []
      }
    };
  }
}
