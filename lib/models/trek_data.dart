// lib/models/trek_data.dart
// ignore_for_file: constant_identifier_names

enum TrekCategory {
  info,
  route,
  landmarks,
  villages,
  accommodation,
  food_water,
  permits,
  connectivity,
  weather,
  hospitals,
  emergency,
  transport;

  String get value => name;

  static TrekCategory? fromString(String val) {
    final clean = val.toLowerCase().replaceAll('-', '_').trim();
    for (final cat in TrekCategory.values) {
      if (cat.name == clean) return cat;
    }
    return null;
  }
}

class TrekData {
  final String id;
  final List<String> aliases;
  final Map<TrekCategory, Map<String, dynamic>> details;

  TrekData({required this.id, required this.aliases, required this.details});

  factory TrekData.fromJson(Map<String, dynamic> json) {
    final detailsMap = <TrekCategory, Map<String, dynamic>>{};
    final rawDetails = json['details'] as Map<String, dynamic>? ?? const {};

    for (final key in rawDetails.keys) {
      final category = TrekCategory.fromString(key);
      if (category != null) {
        final catMap = Map<String, dynamic>.from(
          rawDetails[key] as Map? ?? const {},
        );
        final infoList = List<String>.from(
          catMap['information'] as List? ?? const [],
        );
        final addInfoList = List<String>.from(
          catMap['additional_information'] as List? ?? const [],
        );
        detailsMap[category] = {
          'information': infoList,
          'additional_information': addInfoList,
        };
      }
    }

    return TrekData(
      id: json['id'] as String? ?? '',
      aliases: List<String>.from(json['aliases'] ?? const []),
      details: detailsMap,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'aliases': aliases,
    'details': details.map((k, v) => MapEntry(k.name, v)),
  };
}
