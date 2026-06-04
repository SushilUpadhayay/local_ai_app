import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/app_state.dart';

class VoiceWaveformSheet extends StatefulWidget {
  final AppState appState;

  const VoiceWaveformSheet({super.key, required this.appState});

  @override
  State<VoiceWaveformSheet> createState() => _VoiceWaveformSheetState();
}

class _VoiceWaveformSheetState extends State<VoiceWaveformSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.appState.voiceState == VoiceState.idle) {
      return const SizedBox.shrink();
    }

    final voiceState = widget.appState.voiceState;
    final String statusText = _getStatusText(voiceState);
    final Color waveColor = _getWaveColor(voiceState);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF151E2E), // Card Surface
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        border: Border(
          top: BorderSide(color: Color(0xFF1E293B)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status text
          Text(
            statusText,
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),

          // Animated Waveform Row or Error Container
          if (voiceState == VoiceState.error) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEF4444).withAlpha(50)),
              ),
              child: Text(
                widget.appState.voiceErrorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFCA5A5),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
            if (widget.appState.voiceErrorMessage.toLowerCase().contains('permission') ||
                widget.appState.voiceErrorMessage.toLowerCase().contains('settings')) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  await openAppSettings();
                },
                icon: const Icon(Icons.settings, size: 16, color: Colors.white),
                label: const Text(
                  'OPEN SETTINGS',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ] else
            SizedBox(
              height: 48,
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: List.generate(9, (index) {
                      double scale = _getBarScale(index, voiceState);
                      double height = 8 + (36 * scale);
                      return Container(
                        width: 4,
                        height: height,
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        decoration: BoxDecoration(
                          color: waveColor.withAlpha(204),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          const SizedBox(height: 20),

          // Action button
          GestureDetector(
            onTap: () {
              if (voiceState == VoiceState.speaking) {
                widget.appState.stopSpeaking();
              } else if (voiceState == VoiceState.error) {
                widget.appState.clearVoiceError();
              } else {
                widget.appState.cancelVoiceSession();
              }
            },
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: waveColor.withAlpha(25),
                border: Border.all(
                  color: waveColor.withAlpha(102),
                  style: BorderStyle.solid,
                ),
              ),
              child: Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: waveColor,
                    boxShadow: [
                      BoxShadow(
                        color: waveColor.withAlpha(102),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    () {
                      switch (voiceState) {
                        case VoiceState.listening:
                          return Icons.mic_off;
                        case VoiceState.speaking:
                          return Icons.volume_off_rounded;
                        case VoiceState.error:
                          return Icons.close_rounded;
                        default:
                          return Icons.mic_none;
                      }
                    }(),
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            () {
              switch (voiceState) {
                case VoiceState.speaking:
                  return 'TAP TO STOP SPEAKING';
                case VoiceState.error:
                  return 'TAP TO DISMISS';
                default:
                  return 'TAP TO CANCEL / RETURN';
              }
            }(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(VoiceState state) {
    switch (state) {
      case VoiceState.listening:
        return 'Listening...';
      case VoiceState.processing:
        return 'Processing Locally...';
      case VoiceState.speaking:
        return 'Speaking Answer...';
      case VoiceState.error:
        return 'Voice Error';
      default:
        return '';
    }
  }

  Color _getWaveColor(VoiceState state) {
    switch (state) {
      case VoiceState.listening:
        return const Color(0xFF6366F1); // Indigo
      case VoiceState.processing:
        return const Color(0xFF94A3B8); // Slate Grey
      case VoiceState.speaking:
        return const Color(0xFF10B981); // Emerald Green
      case VoiceState.error:
        return const Color(0xFFEF4444); // Red
      default:
        return const Color(0xFF6366F1);
    }
  }

  double _getBarScale(int index, VoiceState state) {
    if (state == VoiceState.processing) {
      // Slow pulse animation
      return 0.3 + 0.4 * math.sin((_animationController.value * 2 * math.pi) + (index * 0.5));
    }

    // Waveform simulation
    double offset = index * 0.4;
    double frequency = state == VoiceState.speaking ? 2.5 : 1.5;
    double animValue = _animationController.value * 2 * math.pi;

    // Distribute peaks inside the middle bars
    double centerScale = 1.0 - (index - 4).abs() / 5.0; // Peak in the center (index 4)

    return centerScale * (0.3 + 0.7 * (0.5 + 0.5 * math.sin((animValue * frequency) + offset)));
  }
}
