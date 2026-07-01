import '../models/tool_result.dart';

class ToolResultPromptBuilder {
  const ToolResultPromptBuilder._();
  static String build({required String question, required ToolResult result}) {
    final buf = StringBuffer();

    buf
      ..writeln('User Question:')
      ..writeln(_clean(question, fallback: 'General trek information request.'))
      ..writeln();

    final displayName = result.trekDisplayName.isNotEmpty
        ? result.trekDisplayName
        : _toTitleCase(result.trekName);
    final aliasLine = result.aliases.isNotEmpty
        ? ' (also known as: ${result.aliases.join(', ')})'
        : '';
    buf
      ..writeln('Trek:')
      ..writeln('$displayName$aliasLine')
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

  static String _toTitleCase(String snakeCase) {
    return snakeCase
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
