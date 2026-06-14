// lib/models/trek_data.dart

enum TrekCategory {
  route,
  hospitals,
  villages,
  landmarks,
  transport,
  emergency,
  food_water,
  geography,
  permits,
  accommodation,
  internet,
  weather,
  wildlife,
  gps,              // Reserved for future use
  maps,             // Reserved for future use
  nearby_locations; // Reserved for future use

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
  final Map<String, dynamic> overview;
  final Map<TrekCategory, Map<String, dynamic>> details;
  final List<Map<String, String>> faq;

  TrekData({
    required this.id,
    required this.aliases,
    required this.overview,
    required this.details,
    required this.faq,
  });

  factory TrekData.fromJson(Map<String, dynamic> json) {
    final detailsMap = <TrekCategory, Map<String, dynamic>>{};
    final rawDetails = json['details'] as Map<String, dynamic>? ?? const {};
    
    for (final key in rawDetails.keys) {
      final category = TrekCategory.fromString(key);
      if (category != null) {
        detailsMap[category] = Map<String, dynamic>.from(rawDetails[key] as Map? ?? const {});
      }
    }

    final rawFaq = json['faq'] as List? ?? const [];
    final faqList = rawFaq.map((item) {
      final m = Map<String, dynamic>.from(item as Map);
      return {
        'question': m['question']?.toString() ?? '',
        'answer': m['answer']?.toString() ?? '',
      };
    }).toList();

    return TrekData(
      id: json['id'] as String? ?? '',
      aliases: List<String>.from(json['aliases'] ?? const []),
      overview: Map<String, dynamic>.from(json['overview'] as Map? ?? const {}),
      details: detailsMap,
      faq: faqList,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'aliases': aliases,
    'overview': overview,
    'details': details.map((k, v) => MapEntry(k.name, v)),
    'faq': faq,
  };
}
