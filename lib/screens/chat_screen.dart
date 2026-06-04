import 'dart:async';
import 'package:flutter/material.dart';
import '../models/app_state.dart';
import '../models/conversation.dart';

class ChatScreen extends StatefulWidget {
  final AppState appState;
  const ChatScreen({super.key, required this.appState});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Animation controller for the loading-model shimmer pulse
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // Helpers

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isNotEmpty) {
      widget.appState.sendMessage(text);
      _inputController.clear();
      Future.delayed(const Duration(milliseconds: 80), _scrollToBottom);
    }
  }

  void _applySuggestion(String suggestion) {
    _inputController.text = suggestion;
  }

  // Build

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final activeConv = appState.activeConversation;
    final loadState = appState.modelLoadState;
    final isListEmpty = activeConv == null || activeConv.messages.isEmpty;

    return Stack(
      children: [
        // Main chat column
        Column(
          children: [
            // Model-state banner (shown when not loaded)
            _buildModelStateBanner(loadState, appState),

            // Message list or welcome screen
            Expanded(
              child: isListEmpty
                  ? _buildWelcomeSuggestions(loadState)
                  : _buildMessagesList(activeConv.messages, appState),
            ),

            // Input row (shown during idle, listening, or error so user can see transcription and edit)
            if (appState.voiceState == VoiceState.idle ||
                appState.voiceState == VoiceState.listening ||
                appState.voiceState == VoiceState.error)
              _buildInputRow(appState),
          ],
        ),

        // "Loading Model…" full-screen overlay
        if (loadState == ModelLoadState.loading)
          _buildLoadingOverlay(appState.modelStatusMessage),
      ],
    );
  }

  //  BANNERS
  Widget _buildModelStateBanner(ModelLoadState state, AppState appState) {
    if (state == ModelLoadState.loaded || state == ModelLoadState.loading) {
      return const SizedBox.shrink();
    }

    if (state == ModelLoadState.failed) {
      return _buildBanner(
        icon: Icons.error_outline_rounded,
        iconColor: const Color(0xFFEF4444),
        bgColor: const Color(0xFFEF4444).withAlpha(20),
        borderColor: const Color(0xFFEF4444).withAlpha(60),
        message: appState.modelStatusMessage.isNotEmpty
            ? appState.modelStatusMessage
            : 'Model failed to load. Please retry from Local Models.',
        trailing: TextButton(
          onPressed: () => appState.switchScreen(AppScreen.models),
          child: const Text(
            'Open Models',
            style: TextStyle(
              color: Color(0xFFEF4444),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    // unloaded
    if (appState.activeModel == null) {
      return _buildBanner(
        icon: Icons.memory_rounded,
        iconColor: const Color(0xFFF59E0B),
        bgColor: const Color(0xFFF59E0B).withAlpha(18),
        borderColor: const Color(0xFFF59E0B).withAlpha(55),
        message: 'No model loaded. Download and activate a model to chat.',
        trailing: TextButton(
          onPressed: () => appState.switchScreen(AppScreen.models),
          child: const Text(
            'Open Models',
            style: TextStyle(
              color: Color(0xFFF59E0B),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    // installed but not yet loaded into engine
    return _buildBanner(
      icon: Icons.offline_bolt_rounded,
      iconColor: const Color(0xFF6366F1),
      bgColor: const Color(0xFF6366F1).withAlpha(18),
      borderColor: const Color(0xFF6366F1).withAlpha(55),
      message:
          '${appState.activeModel!.name} is installed but not loaded. Tap Set Active to initialise.',
      trailing: TextButton(
        onPressed: () => appState.switchScreen(AppScreen.models),
        child: const Text(
          'Load Model',
          style: TextStyle(
            color: Color(0xFF6366F1),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildBanner({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required Color borderColor,
    required String message,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 11, color: iconColor, height: 1.3),
            ),
          ),
          // ignore: use_null_aware_elements
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  //  LOADING OVERLAY

  Widget _buildLoadingOverlay(String message) {
    return Container(
      color: const Color(0xFF0B0F19).withAlpha(210),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated pulsing brain icon
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (ctx, _) {
                return Opacity(
                  opacity: _pulseAnim.value,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF6366F1).withAlpha(30),
                      border: Border.all(
                        color: const Color(0xFF6366F1).withAlpha(100),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.psychology_rounded,
                      color: Color(0xFF6366F1),
                      size: 38,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text(
              'Loading Model…',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 240,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 180,
              child: LinearProgressIndicator(
                backgroundColor: Color(0xFF1E293B),
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                minHeight: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  //  WELCOME / SUGGESTIONS

  Widget _buildWelcomeSuggestions(ModelLoadState state) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF6366F1).withAlpha(25),
                border: Border.all(color: const Color(0xFF6366F1), width: 1),
              ),
              child: const Icon(
                Icons.psychology,
                color: Color(0xFF6366F1),
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Offline-First AI',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              state == ModelLoadState.loaded
                  ? 'Your model is ready. Ask anything — 100% on-device.'
                  : 'Load a model from Local Models to start chatting privately.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF94A3B8),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            ...[
              'Draft an email to schedule a sync',
              'Explain quantum physics simply',
              'Write a clean JavaScript utility',
            ].map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildSuggestionCard(s),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(String text) {
    return GestureDetector(
      onTap: () => _applySuggestion(text),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF151E2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: Text(
          '$text…',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
        ),
      ),
    );
  }

  //  MESSAGE LIST  (with live streaming bubble)

  Widget _buildMessagesList(List<Message> messages, AppState appState) {
    // While streaming, we append a virtual streaming bubble after the last
    // committed message.
    final showStreamingBubble =
        appState.isStreaming && appState.streamingToken.isNotEmpty;

    final itemCount =
        messages.length + (appState.isAiTyping || showStreamingBubble ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Last item — typing / streaming indicator
        if (index == messages.length) {
          if (showStreamingBubble) {
            return _buildStreamingBubble(appState.streamingToken);
          }
          return _buildTypingIndicatorBubble();
        }

        final msg = messages[index];
        final isUser = msg.sender == 'user';
        return _buildMessageBubble(msg, isUser);
      },
    );
  }

  Widget _buildMessageBubble(Message msg, bool isUser) {
    final isSpeakingThis =
        widget.appState.currentlySpeakingMessage == msg &&
        widget.appState.voiceState == VoiceState.speaking;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8.0, right: 4.0),
              child: IconButton(
                icon: Icon(
                  isSpeakingThis
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  color: isSpeakingThis
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF94A3B8),
                  size: 20,
                ),
                onPressed: () => widget.appState.speakMessage(msg),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                splashRadius: 18,
              ),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFF6366F1)
                    : const Color(0xFF151E2E),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser
                    ? null
                    : Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Column(
                crossAxisAlignment: isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    msg.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isUser && msg.model != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            msg.model!,
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        _formatTime(msg.timestamp),
                        style: TextStyle(
                          fontSize: 9,
                          color: isUser
                              ? Colors.white.withAlpha(178)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Live streaming bubble — shows accumulated tokens as they arrive.
  /// Includes optional "🔊 Speak Live" button for real-time TTS
  Widget _buildStreamingBubble(String partialText) {
    final appState = widget.appState;
    final isLiveSpeaking = appState.isLiveStreamingTts;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live TTS button (optional feature)
          Padding(
            padding: const EdgeInsets.only(top: 8.0, right: 4.0),
            child: GestureDetector(
              onTap: () {
                if (isLiveSpeaking) {
                  // Stop live TTS (keep generation running)
                  appState.stopLiveStreamingTts();
                } else {
                  // Start live TTS
                  appState.startLiveStreamingTts();
                }
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isLiveSpeaking
                      ? const Color(0xFFEF4444).withAlpha(25)
                      : const Color(0xFF1E293B),
                  border: Border.all(
                    color: isLiveSpeaking
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF94A3B8),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    isLiveSpeaking ? '⏹' : '🔊',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ),
          ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF151E2E),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    partialText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Blinking cursor indicator
                  _BlinkingCursor(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicatorBubble() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF151E2E),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => _TypingDotAnimation(index: i)),
            ),
          ),
        ],
      ),
    );
  }

  //  INPUT ROW

  Widget _buildInputRow(AppState appState) {
    final canSend =
        appState.modelLoadState == ModelLoadState.loaded &&
        !appState.isStreaming;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Row(
        children: [
          // Pill text field
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF151E2E),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      enabled: !appState.isStreaming,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: appState.isStreaming
                            ? 'AI is responding…'
                            : appState.modelLoadState != ModelLoadState.loaded
                            ? 'Load a model to start chatting…'
                            : 'Ask anything…',
                        hintStyle: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onSubmitted: canSend ? (_) => _sendMessage() : null,
                    ),
                  ),
                  // PUSH-TO-TALK: Microphone button
                  // Tap 1: Start recording (state = listening, icon = stop circle)
                  // Tap 2: Stop recording and transcribe (state = processing)
                  // Result: Text appears in input field (NOT automatically sent)
                  // User can edit and manually press Send to trigger LLM
                  IconButton(
                    icon: Icon(
                      appState.voiceState == VoiceState.listening
                          ? Icons.stop_circle_rounded
                          : Icons.mic,
                      color: appState.voiceState == VoiceState.listening
                          ? const Color(0xFFEF4444)
                          : canSend
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF334155),
                      size: 20,
                    ),
                    onPressed: appState.voiceState == VoiceState.listening
                        ? () => appState.cancelVoiceSession()
                        : canSend
                        ? () {
                            FocusScope.of(context).unfocus();
                            appState.startVoiceSession(_inputController);
                          }
                        : null,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button - MANUALLY triggered (not automatic)
          // Only sends message when user explicitly presses this button
          GestureDetector(
            onTap: appState.isStreaming
                ? null // streaming — no action yet (stop can be wired here)
                : canSend
                ? _sendMessage
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: canSend
                    ? const Color(0xFF6366F1)
                    : const Color(0xFF1E293B),
                boxShadow: canSend
                    ? [
                        const BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ]
                    : [],
              ),
              child: Icon(
                appState.isStreaming ? Icons.stop_rounded : Icons.send_rounded,
                color: canSend ? Colors.white : const Color(0xFF334155),
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  //  UTILS

  String _formatTime(DateTime time) {
    final hour = time.hour > 12
        ? time.hour - 12
        : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute < 10 ? '0${time.minute}' : '${time.minute}';
    final ampm = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }
}

//  ANIMATED WIDGETS
/// A small blinking `|` cursor shown at the end of the streaming bubble.
class _BlinkingCursor extends StatefulWidget {
  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Opacity(
        opacity: _ctrl.value,
        child: Container(
          width: 2,
          height: 14,
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}

/// Bouncing dot animation for the typing indicator.
class _TypingDotAnimation extends StatefulWidget {
  final int index;
  const _TypingDotAnimation({required this.index});

  @override
  State<_TypingDotAnimation> createState() => _TypingDotAnimationState();
}

class _TypingDotAnimationState extends State<_TypingDotAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _animation = Tween<double>(begin: 0, end: 6).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(
          widget.index * 0.15,
          0.5 + widget.index * 0.15,
          curve: Curves.easeInOut,
        ),
      ),
    );

    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          transform: Matrix4.translationValues(0, -_animation.value, 0),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF94A3B8),
          ),
        );
      },
    );
  }
}
