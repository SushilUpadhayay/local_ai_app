import 'package:flutter_test/flutter_test.dart';
import 'dart:isolate';
import 'dart:io';

void main() {
  test('print whisper_flutter_new source code', () async {
    final uri = Uri.parse('package:whisper_flutter_new/whisper_flutter_new.dart');
    final resolvedUri = await Isolate.resolvePackageUri(uri);
    print('Resolved package URI: $resolvedUri');
    
    if (resolvedUri != null) {
      final file = File.fromUri(resolvedUri);
      if (file.existsSync()) {
        print('--- whisper_flutter_new.dart source: ---');
        print(file.readAsStringSync());
        print('-----------------------------------------');
      } else {
        print('File does not exist.');
      }
    } else {
      print('Could not resolve package URI.');
    }
  });
}
