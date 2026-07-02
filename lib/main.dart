import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models/app_state.dart';
import 'widgets/sidebar_drawer.dart';
import 'widgets/voice_waveform_sheet.dart';
import 'screens/chat_screen.dart';
import 'screens/history_screen.dart';
import 'screens/models_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Override debugPrint to print directly to stdout/terminal
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      print(message);
    }
  };

  runApp(const LocalAiApp());
}

class LocalAiApp extends StatelessWidget {
  const LocalAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B0F19),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Colors.white),
        ),
        cardColor: const Color(0xFF151E2E),
        dividerColor: const Color(0xFF1E293B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1), // Indigo Accent
          surface: Color(0xFF151E2E),
          secondary: Color(0xFF10B981), // Emerald Green
        ),
      ),
      home: const MainScaffold(),
    );
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  final AppState _appState = AppState();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void dispose() {
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _appState,
      builder: (context, child) {
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: const Color(0xFF0B0F19),

          // Header App Bar
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.menu, size: 22),
              onPressed: () {
                _scaffoldKey.currentState?.openDrawer();
              },
            ),
            title: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Local AI',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 5, color: Color(0xFF10B981)),
                      SizedBox(width: 4),
                      Text(
                        'OFFLINE MODE',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              GestureDetector(
                onTap: _showTrekSelectionDialog,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 190),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151E2E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _appState.hasSelectedTrek
                            ? const Color(0xFF10B981).withAlpha(120)
                            : const Color(0xFF1E293B),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hiking_rounded,
                          size: 13,
                          color: _appState.hasSelectedTrek
                              ? const Color(0xFF10B981)
                              : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _appState.hasSelectedTrek
                                ? _appState.selectedTrekLabel
                                : 'Select Trek',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Active Model Pill
              GestureDetector(
                onTap: () {
                  _appState.switchScreen(AppScreen.models);
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151E2E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _appState.activeModel != null
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF59E0B).withAlpha(80),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 6,
                          color: () {
                            if (_appState.activeModel == null) {
                              return const Color(0xFFF59E0B);
                            }
                            switch (_appState.modelLoadState) {
                              case ModelLoadState.loaded:
                                return const Color(0xFF10B981);
                              case ModelLoadState.loading:
                                return const Color(0xFFF59E0B);
                              case ModelLoadState.failed:
                                return const Color(0xFFEF4444);
                              case ModelLoadState.unloaded:
                                return const Color(0xFF94A3B8);
                            }
                          }(),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _appState.activeModel?.name ?? 'No Model',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Sidebar Navigation Drawer
          drawer: SidebarDrawer(appState: _appState),

          // Core Body switcher
          body: Column(
            children: [
              // Divider separating header from main body
              const Divider(color: Color(0xFF1E293B), height: 1),

              // Active screen display area
              Expanded(child: _buildActiveScreen()),

              // Voice overlay sheets (displays automatically when voice is activated)
              if (_appState.voiceState != VoiceState.idle)
                VoiceWaveformSheet(appState: _appState),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showTrekSelectionDialog() async {
    final treks = _appState.availableTreks;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151E2E),
          title: const Text('Trek Selection'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (treks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No offline treks are loaded yet.',
                      style: TextStyle(color: Color(0xFF94A3B8)),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: treks.length,
                      separatorBuilder: (context, index) =>
                          const Divider(color: Color(0xFF1E293B), height: 1),
                      itemBuilder: (context, index) {
                        final trek = treks[index];
                        final trekName = trek['trek_name']?.toString() ?? '';
                        final selected = trekName == _appState.selectedTrekName;
                        return ListTile(
                          leading: Icon(
                            selected
                                ? Icons.check_circle_rounded
                                : Icons.landscape_rounded,
                            color: selected
                                ? const Color(0xFF10B981)
                                : const Color(0xFF94A3B8),
                          ),
                          title: Text(
                            trek['name']?.toString() ?? trekName,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            [
                              if (trek['difficulty'] != null)
                                trek['difficulty'].toString(),
                              if (trek['duration_days'] != null)
                                '${trek['duration_days']} days',
                            ].join(' - '),
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                            ),
                          ),
                          onTap: trekName.isEmpty
                              ? null
                              : () {
                                  _appState.selectTrek(trekName);
                                  Navigator.pop(dialogContext);
                                },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _appState.hasSelectedTrek
                  ? () {
                      _appState.clearSelectedTrek();
                      Navigator.pop(dialogContext);
                    }
                  : null,
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActiveScreen() {
    switch (_appState.activeScreen) {
      case AppScreen.chat:
        return ChatScreen(appState: _appState);
      case AppScreen.history:
        return HistoryScreen(appState: _appState);
      case AppScreen.models:
        return ModelsScreen(appState: _appState);
    }
  }
}
