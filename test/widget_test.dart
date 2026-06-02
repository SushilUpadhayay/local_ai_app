import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_app/models/app_state.dart';

void main() {
  // Ensure Flutter binding is initialized for services/plugins
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppState instantiation unit test', () {
    final appState = AppState();
    expect(appState.activeScreen, AppScreen.chat);
    expect(appState.isLoading, true); // initially loading
    expect(appState.isStreaming, false);
  });
}
