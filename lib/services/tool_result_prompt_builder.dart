import '../models/tool_result.dart';

class ToolResultPromptBuilder {
  const ToolResultPromptBuilder._();

  static String build({
    required String question,
    required ToolResult result,
  }) {
    final buf = StringBuffer()
      ..writeln('Trek:')
      ..writeln(_clean(result.trekName, fallback: 'none'))
      ..writeln()
      ..writeln('Question:')
      ..writeln(_clean(question, fallback: 'none'))
      ..writeln()
      ..writeln('Category:')
      ..writeln(_clean(result.category, fallback: 'none'))
      ..writeln()
      ..writeln('Information:');

    for (final fact in _itemsOrFallback(
      result.information,
      'No offline information was returned.',
    )) {
      buf.writeln('- $fact');
    }

    buf
      ..writeln()
      ..writeln('Additional Information:');

    for (final note in _itemsOrFallback(
      result.additionalInformation,
      'None.',
    )) {
      buf.writeln('- $note');
    }

    return buf.toString().trimRight();
  }

  static List<String> _itemsOrFallback(List<String> items, String fallback) {
    final cleanItems = items
        .map((item) => _clean(item))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return cleanItems.isEmpty ? [fallback] : cleanItems;
  }

  static String _clean(String value, {String fallback = ''}) {
    final clean = value.trim();
    return clean.isEmpty ? fallback : clean;
  }
}
