import 'package:flutter/foundation.dart';

class DiagnosticLogger {
  static final Map<int, Stopwatch> _stopwatches = {};

  static void logStart(int step, String name) {
    final sw = Stopwatch()..start();
    _stopwatches[step] = sw;
    final msg = '[STARTUP_DIAGNOSTIC] Step $step: $name - START';
    print(msg);
  }

  static void logSuccess(int step, String name) {
    final sw = _stopwatches[step];
    int elapsed = 0;
    if (sw != null) {
      sw.stop();
      elapsed = sw.elapsedMilliseconds;
    }
    final msg = '[STARTUP_DIAGNOSTIC] Step $step: $name - SUCCESS (Duration: ${elapsed}ms)';
    print(msg);
  }

  static void logFailure(int step, String name, Object error, [StackTrace? stack]) {
    final sw = _stopwatches[step];
    int elapsed = 0;
    if (sw != null) {
      sw.stop();
      elapsed = sw.elapsedMilliseconds;
    }
    final msg = '[STARTUP_DIAGNOSTIC] Step $step: $name - FAILURE (Duration: ${elapsed}ms, Exception: $error)';
    print(msg);
    if (stack != null) {
      print(stack);
    }
  }
}
