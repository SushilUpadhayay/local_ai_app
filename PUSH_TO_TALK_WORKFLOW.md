# Push-to-Talk (PTT) STT Workflow

This document explains how the speech-to-text (STT) system works in this app.

## Overview

The app uses a **PUSH-TO-TALK** model for speech input, NOT continuous listening or automatic processing.

**Key Principles:**
- User manually controls when recording starts/stops
- No continuous background listening
- No automatic message sending
- Transcription results are placed in the input field for review/editing
- Only manual "Send" button press triggers the LLM

## User Workflow

### Step 1: Start Recording
1. User taps the **microphone button** in the chat input area
2. Microphone button changes appearance (becomes red stop circle)
3. Audio recording starts (shown in voice modal with animated waveform)
4. Status: "RECORDING... Tap to stop"

### Step 2: Stop Recording
1. User taps the **microphone button again** (now showing as stop circle)
2. Recording stops immediately
3. Voice modal changes to "Transcribing with Whisper..." 
4. Status: "Processing... Do not close" with pulse animation

### Step 3: Whisper Transcription
1. Recorded audio is sent to Whisper speech recognition model
2. Whisper transcribes the audio to text (runs locally on device)
3. This happens asynchronously (user interface remains responsive)

### Step 4: Text in Input Field
1. Transcription result is placed in the chat input field
2. Voice modal closes automatically
3. Text is ready for review/editing

**IMPORTANT:** The text is NOT automatically sent to the LLM yet

### Step 5: Review & Edit
1. User can review the transcribed text
2. User can edit it if needed
3. User can add more text
4. User can delete text

### Step 6: Manual Send
1. User presses the **Send button** (blue circle with arrow)
2. Message is sent to the LLM
3. LLM generates a response
4. Response is displayed in the chat

## Code Architecture

### Key Files

**1. `lib/models/app_state.dart`**
- `startVoiceSession()` - Initiates recording
- `cancelVoiceSession()` - Stops recording and triggers transcription
- `sendMessage()` - ONLY method that triggers LLM (manual only)

**2. `lib/services/stt_service.dart`**
- `WhisperSttService` - Handles audio recording and Whisper transcription
- `startListening()` - Starts audio recording
- `stopListening()` - Stops recording and sends to Whisper

**3. `lib/screens/chat_screen.dart`**
- Microphone button - Calls `startVoiceSession()` and `cancelVoiceSession()`
- Send button - Calls `sendMessage()`

**4. `lib/widgets/voice_waveform_sheet.dart`**
- Displays recording/transcription status with animations
- Shows error messages if needed

### State Machine

The `VoiceState` enum tracks the voice workflow:

```
    idle (initial state)
      ↓
   [User taps mic] → listening (recording)
      ↓
   [User taps mic] → processing (Whisper transcribing)
      ↓
    idle (transcription complete, text in field)
```

### No Automatic Behaviors

**These do NOT happen automatically:**

```dart
// ❌ NOT automatic:
- sendMessage() is NOT called after transcription
- LLM is NOT invoked after transcription
- Message is NOT sent automatically
```

**Only triggered manually:**
```dart
// ✅ Manual only:
- Recording stops only when user taps mic again
- Transcription starts only when recording stops
- Message sends only when user presses Send button
- LLM responds only after message is sent
```

## Technical Implementation

### Recording Audio
- Uses `record` package with `AudioRecorder`
- Records to `/tmp/whisper_record.wav`
- Format: WAV, 16kHz, Mono
- No background recording, only when user has recording active

### Transcription
- Uses Whisper local model (tiny/base/small)
- Runs on device (no cloud/API calls)
- Language detection set to Nepali (`'ne'`) by default
- Can be changed to English (`'en'`) or auto-detect (`'auto'`)

### Text Placement
```dart
// After transcription completes:
inputController.text = transcribedText;  // Text in input field
// User must now manually press Send
sendMessage(inputController.text);  // Only when user presses Send
```

### No Hidden Automatic Behaviors

The `onResult` callback in `startVoiceSession()`:
```dart
onResult: (text) {
  inputController.text = text;  // Place text in field
  // ❌ NO automatic sendMessage() call here
  // ❌ NO automatic LLM invocation here
  _voiceState = VoiceState.idle;
  notifyListeners();
}
```

## Voice State Transitions

| State | Meaning | Duration | What Shows |
|-------|---------|----------|-----------|
| `idle` | Normal state, no voice activity | - | Nothing (modal hidden) |
| `listening` | User is recording audio | User-controlled | "RECORDING... Tap to stop" with waveform |
| `processing` | Whisper is transcribing | Seconds to minutes | "Transcribing..." with pulse |
| `speaking` | TTS is playing response | Automatic | "Speaking Answer..." with waveform |
| `error` | Error occurred | - | Error message with details |

## Customization Options

### Change Recording Language
In `app_state.dart`, `startVoiceSession()`:
```dart
// Currently: Nepali
await _sttService.startListening(
  localeId: 'ne',  // Change 'ne' to 'en' for English, or null for auto-detect
  // ...
);
```

### Change Whisper Model
Available models: tiny, base, small (configured in Models screen)

### Disable Voice Feature
Simply don't tap the microphone button. Voice is completely optional.

## Testing the Workflow

To verify push-to-talk is working correctly:

1. ✅ Tap mic → should start recording (see waveform modal)
2. ✅ Speak something → should hear nothing (just recording)
3. ✅ Tap mic again → should stop and process
4. ✅ See transcription appear in input field
5. ✅ Edit the text (optional)
6. ✅ Tap Send → LLM should respond
7. ✅ Response should appear in chat

If any step doesn't follow this order, the push-to-talk workflow is not working correctly.

## Common Issues

### Problem: Text sent automatically
**Solution:** This should not happen. Check that `sendMessage()` is not called in `onResult` callback.

### Problem: Continuous recording
**Solution:** Recording should stop only when user taps mic button again. Not continuous.

### Problem: No text appears
**Solution:** Check that Whisper model is downloaded and active. Check logs for transcription errors.

### Problem: Text appears but LLM doesn't respond
**Solution:** This is normal - user must press Send button. Tap the blue Send button to trigger LLM.

## Architecture Benefits

**Why Push-to-Talk instead of continuous listening?**

1. ✅ **Explicit control** - User decides when to record
2. ✅ **Battery efficient** - No continuous background processing
3. ✅ **User privacy** - Recording only when user initiates
4. ✅ **Clear workflow** - User understands each step
5. ✅ **No false triggers** - App doesn't start recording accidentally
6. ✅ **Deliberate messaging** - User can review before sending
7. ✅ **Offline friendly** - No cloud dependency, runs locally

## Future Enhancements

Possible improvements while maintaining push-to-talk model:

- [ ] Voice activity detection (auto-stop when user pauses)
- [ ] Recording duration limit
- [ ] Multiple language support in settings
- [ ] Audio visualization improvements
- [ ] Undo/retry transcription
- [ ] Alternative input methods (keyboard, dictation)

---

**Key Takeaway:** This is a simple, user-controlled, push-to-talk system. No automatic sending. No continuous listening. User controls everything.
