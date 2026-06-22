import 'trek_data.dart';

class ToolResult {
  final String trekName;
  final String category;
  final List<String> information;
  final List<String> additionalInformation;

  static final List<String> supportedTrekCategories = TrekCategory.values
      .map((category) => category.name)
      .toList(growable: false);

  ToolResult({
    required String trekName,
    required this.category,
    required List<String> information,
    List<String> additionalInformation = const [],
  }) : trekName = trekName.trim().isEmpty ? 'none' : trekName.trim(),
       information = List.unmodifiable(
         information
             .map((item) => item.trim())
             .where((item) => item.isNotEmpty),
       ),
       additionalInformation = List.unmodifiable(
         additionalInformation
             .map((item) => item.trim())
             .where((item) => item.isNotEmpty),
       );

  factory ToolResult.empty({
    required String trekName,
    required String category,
  }) {
    return ToolResult(
      trekName: trekName,
      category: category,
      information: const ['No offline information was returned.'],
    );
  }

  factory ToolResult.error({
    required String trekName,
    required String category,
    required String message,
  }) {
    return ToolResult(
      trekName: trekName,
      category: category,
      information: [message],
    );
  }

  Map<String, dynamic> toMap() => {
    'trekName': trekName,
    'category': category,
    'information': information,
    'additionalInformation': additionalInformation,
  };
}
