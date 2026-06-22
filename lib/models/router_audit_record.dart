/// A single structured record of a Pass 1 router classification decision.
///
/// Stored in [AppState._routerAuditLog] so callers can query session accuracy,
/// count mismatches, and serialize audit trails — rather than relying on
/// ephemeral debugPrint output.
class RouterAuditRecord {
  final String userQuery;
  final String routerRawOutput;
  final String selectedTrekName;
  final String expectedType;
  final String expectedTool;
  final String expectedCategory;
  final String actualType;
  final String actualTool;
  final String actualCategory;
  final bool mismatch;
  final DateTime timestamp;

  const RouterAuditRecord({
    required this.userQuery,
    required this.routerRawOutput,
    required this.selectedTrekName,
    required this.expectedType,
    required this.expectedTool,
    required this.expectedCategory,
    required this.actualType,
    required this.actualTool,
    required this.actualCategory,
    required this.mismatch,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
    'timestamp': timestamp.toIso8601String(),
    'mismatch': mismatch,
    'userQuery': userQuery,
    'selectedTrekName': selectedTrekName,
    'expected': {
      'type': expectedType,
      'tool': expectedTool,
      'category': expectedCategory,
    },
    'actual': {
      'type': actualType,
      'tool': actualTool,
      'category': actualCategory,
    },
    'routerRawOutput': routerRawOutput,
  };
}
