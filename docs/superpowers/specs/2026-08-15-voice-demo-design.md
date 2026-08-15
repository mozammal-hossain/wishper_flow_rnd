# Voice Demo: On-device Speech-to-Text & Text-to-Speech

## Goal

Replace the default Flutter counter screen with a "Voice Demo" screen
that demonstrates two capabilities, fully on-device:

- **Speech-to-text (STT)**: record the user's voice and transcribe it
  using an on-device Whisper model (via whisper.cpp).
- **Text-to-speech (TTS)**: speak arbitrary typed text using the
  platform's native TTS engine.

No cloud APIs or API keys are involved. Target platforms: iOS and
Android only.

## Packages

| Purpose | Package | Notes |
|---|---|---|
| STT | `whisper_ggml` (^2.6.0) | Wraps whisper.cpp/GGML. Downloads and caches the model on first use. |
| Audio capture | `record` | Records mic input directly as 16kHz mono WAV — the exact format whisper_ggml expects, no conversion needed. |
| TTS | `flutter_tts` | Wraps native iOS (AVSpeechSynthesizer) / Android (TextToSpeech) engines. Works offline once the OS language pack is installed. |

Whisper model: `WhisperModel.base` (~140MB), English (`lang: 'en'`).
Chosen over `tiny` for materially better transcription accuracy, and
over `small`/`medium` to keep the download and inference time
reasonable on mid-range phones.

## UI & flow

Single screen, two sections, no navigation beyond `main.dart` launching
straight into it.

**STT section**
1. User taps a mic button to start recording (`record` package writes
   to a temp WAV file at 16kHz mono).
2. User taps stop. The file is handed to
   `WhisperController.transcribe(model: WhisperModel.base, audioPath: ..., lang: 'en')`.
3. While transcribing, show a loading spinner.
4. On success, the transcript populates an editable text field.
5. On first-ever use, the base model isn't cached yet — show a
   download progress indicator before the mic button is enabled.

**TTS section**
1. A separate, independent text field (not auto-filled from the
   transcript, though the user may copy/paste manually).
2. A "Speak" button calls `flutter_tts` to speak the field's contents.

## Error handling

- Mic permission denied → dialog explaining why the permission is
  needed, with a button to open app settings.
- Model download fails (e.g. no network on first run) → show a retry
  button in place of the progress indicator.
- Transcription returns empty/fails → snackbar error, mic button
  re-enabled for retry.
- TTS engine unavailable or language unsupported → snackbar error.

## Project structure

```
lib/
  services/
    speech_to_text_service.dart   # wraps whisper_ggml + record
    text_to_speech_service.dart   # wraps flutter_tts
  screens/
    voice_demo_screen.dart        # the UI described above
  main.dart                       # updated to launch VoiceDemoScreen
```

Platform config:
- `ios/Runner/Info.plist`: add `NSMicrophoneUsageDescription`.
- `android/app/src/main/AndroidManifest.xml`: add `RECORD_AUDIO`
  permission.

## Testing

- Widget tests for `VoiceDemoScreen` covering UI states (idle,
  recording, transcribing, model-downloading, error) with the two
  services mocked.
- Manual, on-device testing for actual STT/TTS behavior: a real device
  or Android emulator (the iOS simulator has no mic input, so STT
  can't be manually verified there).

## Out of scope (YAGNI)

- Streaming/live transcription (explicitly deferred — record-then-
  transcribe only).
- Desktop platforms (macOS/Windows/Linux).
- Multi-language STT (English-only for now via `base`, not `baseEn`
  specifically chosen to leave a later door open to other languages
  without re-downloading a different model).
- Persisting transcripts/recordings between sessions.
