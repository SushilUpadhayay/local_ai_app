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
      final details = data['details'];

      if (id == null || aliases == null || details == null) {
        debugPrint(
          '[TrekKnowledgeService] WARNING: Skipping $filename — missing required fields (id, aliases, details).',
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

  Map<String, dynamic> get_trek_details(String trekName, String categoryVal) {
    final cacheKey = '${trekName}_$categoryVal';
    return _executeWithCache('get_trek_details', cacheKey, () {
      final trek = _trekData[trekName];
      if (trek == null) {
        return _standardResponse(
          success: false,
          tool: 'get_trek_details',
          trekName: trekName,
          error: 'Trek not found',
          data: {},
        );
      }

      String effectiveCategory = categoryVal;
      if (effectiveCategory == 'itinerary') effectiveCategory = 'route';

      final category = TrekCategory.fromString(effectiveCategory);
      if (category == null) {
        return _standardResponse(
          success: false,
          tool: 'get_trek_details',
          trekName: trekName,
          error: 'Invalid category: $categoryVal',
          data: {},
        );
      }
      final detailData = trek.details[category];
      if (detailData == null) {
        return _standardResponse(
          success: false,
          tool: 'get_trek_details',
          trekName: trekName,
          error: 'Category details not found: ${category.name}',
          data: {},
        );
      }

      return _standardResponse(
        success: true,
        tool: 'get_trek_details',
        trekName: trekName,
        data: {
          'category': category.name,
          'information': detailData['information'] ?? const <String>[],
          'additional_information':
              detailData['additional_information'] ?? const <String>[],
        },
      );
    });
  }

  Map<String, dynamic> list_available_treks() {
    return _executeWithCache('list_available_treks', 'all', () {
      final List<Map<String, dynamic>> treks = [];
      _trekData.forEach((id, trek) {
        final infoDetails = trek.details[TrekCategory.info] ?? const {};
        final infoList = List<String>.from(
          infoDetails['information'] as List? ?? const [],
        );

        String name = id
            .split('_')
            .map(
              (word) =>
                  word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1),
            )
            .join(' ');

        String difficulty = 'Unknown';
        String durationDays = 'Unknown';
        String maxAltitude = 'Unknown';

        for (final sentence in infoList) {
          if (sentence.contains('maximum altitude')) {
            final match = RegExp(
              r'is ([0-9,m\s\(\)ft\x22\x27\u201d\u201c]+)',
              caseSensitive: false,
            ).firstMatch(sentence);
            if (match != null) {
              maxAltitude = match.group(1)!.trim();
            }
          } else if (sentence.contains('standard duration')) {
            final match = RegExp(
              r'is ([^,]+)',
              caseSensitive: false,
            ).firstMatch(sentence);
            if (match != null) {
              durationDays = match.group(1)!.replaceAll('days', '').trim();
            }
          } else if (sentence.contains('is a') &&
              (sentence.contains('trek') || sentence.contains('adventure'))) {
            final match = RegExp(
              r'is a ([^in]+)',
              caseSensitive: false,
            ).firstMatch(sentence);
            if (match != null) {
              var diff = match
                  .group(1)!
                  .replaceAll('trek', '')
                  .replaceAll('adventure', '')
                  .trim();
              if (diff.isNotEmpty) {
                difficulty = diff[0].toUpperCase() + diff.substring(1);
              }
            }
          }
        }

        if (id == 'annapurna_base_camp') name = 'Annapurna Base Camp';
        if (id == 'everest_base_camp') name = 'Everest Base Camp';
        if (id == 'langtang_valley') name = 'Langtang Valley';

        treks.add({
          'trek_name': id,
          'name': name,
          'difficulty': difficulty,
          'duration_days': durationDays,
          'max_altitude': maxAltitude,
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
