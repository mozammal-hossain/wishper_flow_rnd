# Voice Demo (On-device STT + TTS) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the default Flutter counter screen with a "Voice Demo" screen offering on-device speech-to-text (record → transcribe) and text-to-speech (type → speak), no cloud APIs.

**Architecture:** Two thin service classes behind abstract interfaces (`SpeechToTextService`, `TextToSpeechService`) wrap the native plugins, so the UI can be widget-tested against fakes. `VoiceDemoScreen` accepts both services via constructor injection, defaulting to the real implementations.

**Tech Stack:** Flutter 3.44.8 / Dart 3.12.2 (already installed). Packages: `whisper_ggml` (whisper.cpp STT), `record` (mic capture), `flutter_tts` (native TTS), `path_provider` (temp file path for the recording), `permission_handler` (deep-link to app settings on permission denial).

**Spec:** `docs/superpowers/specs/2026-08-15-voice-demo-design.md`

## Global Constraints

- Platforms: iOS and Android only (no desktop).
- `whisper_ggml: ^2.6.0`, `record: ^7.1.1`, `flutter_tts: ^4.2.5`, `path_provider: ^2.1.6`, `permission_handler: ^13.0.1` — exact version constraints, don't substitute other packages.
- Whisper model is `WhisperModel.base`, language fixed to `'en'`. No language picker.
- Recording format must be 16kHz mono WAV (`AudioEncoder.wav`, `sampleRate: 16000`, `numChannels: 1`) — this is what `whisper_ggml` requires without an ffmpeg conversion step.
- `whisper_ggml` has no separate model-download-progress or cache-check API — the model downloads transparently inside `transcribe()`. Do not invent one; use a single loading state for both.
- Record-then-transcribe only. No streaming/live transcription (`transcribeLive` is out of scope).
- No transcript/recording persistence between app sessions.

---

### Task 1: Dependencies and platform permissions

**Files:**
- Modify: `pubspec.yaml`
- Modify: `ios/Runner/Info.plist`
- Modify: `android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Produces: the five packages available for import in later tasks (`whisper_ggml`, `record`, `flutter_tts`, `path_provider`, `permission_handler`).

- [ ] **Step 1: Add the five dependencies to `pubspec.yaml`**

In `pubspec.yaml`, under `dependencies:` (after the existing `cupertino_icons: ^1.0.8` line), add:

```yaml
  whisper_ggml: ^2.6.0
  record: ^7.1.1
  flutter_tts: ^4.2.5
  path_provider: ^2.1.6
  permission_handler: ^13.0.1
```

- [ ] **Step 2: Fetch packages**

Run: `flutter pub get`
Expected: completes with no errors, `pubspec.lock` updates to include the five new packages and their transitive dependencies.

- [ ] **Step 3: Add the microphone usage description to iOS**

In `ios/Runner/Info.plist`, inside the top-level `<dict>` (add it right after the `</array>` that closes `UISupportedInterfaceOrientations~ipad`, before the closing `</dict>`), add:

```xml
	<key>NSMicrophoneUsageDescription</key>
	<string>This app uses the microphone to record your voice for on-device speech-to-text transcription.</string>
```

- [ ] **Step 4: Add the record-audio permission to Android**

In `android/app/src/main/AndroidManifest.xml`, add this line as the first child of `<manifest>` (before the `<application>` element):

```xml
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
```

- [ ] **Step 5: Verify the project still analyzes cleanly**

Run: `flutter analyze`
Expected: `No issues found!` (the existing counter app code is untouched, so this just confirms the new dependencies didn't break anything).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock ios/Runner/Info.plist android/app/src/main/AndroidManifest.xml
git commit -m "chore: add whisper_ggml, record, flutter_tts, path_provider, permission_handler deps and mic permissions"
```

---

### Task 2: Text-to-speech service

**Files:**
- Create: `lib/services/text_to_speech_service.dart`

**Interfaces:**
- Produces: `abstract class TextToSpeechService { Future<void> speak(String text); Future<void> stop(); }` and `class FlutterTextToSpeechService implements TextToSpeechService`, both importable from `package:wishper_flow_rnd/services/text_to_speech_service.dart`.

This is a thin wrapper around a native plugin (`flutter_tts`) with no branching logic of its own — the "don't speak empty text" rule lives in the UI layer (Task 4), not here, so there's nothing here to unit-test without a real device. No automated test for this task; verify by reading the code.

- [ ] **Step 1: Write the service**

Create `lib/services/text_to_speech_service.dart`:

```dart
import 'package:flutter_tts/flutter_tts.dart';

abstract class TextToSpeechService {
  Future<void> speak(String text);
  Future<void> stop();
}

class FlutterTextToSpeechService implements TextToSpeechService {
  FlutterTextToSpeechService() : _tts = FlutterTts();

  final FlutterTts _tts;

  @override
  Future<void> speak(String text) async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.speak(text);
  }

  @override
  Future<void> stop() => _tts.stop();
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/services/text_to_speech_service.dart
git commit -m "feat: add TextToSpeechService wrapping flutter_tts"
```

---

### Task 3: Speech-to-text service

**Files:**
- Create: `lib/services/speech_to_text_service.dart`

**Interfaces:**
- Produces: `abstract class SpeechToTextService { Future<void> startRecording(); Future<String?> stopRecordingAndTranscribe(); }` and `class WhisperSpeechToTextService implements SpeechToTextService`, both importable from `package:wishper_flow_rnd/services/speech_to_text_service.dart`.
- `startRecording()` throws `StateError('Microphone permission denied')` if permission isn't granted — Task 4's UI catches this to show the permission dialog.
- `stopRecordingAndTranscribe()` returns the transcript text, or `null`/empty string if there's nothing to transcribe; it throws if `whisper_ggml`'s `transcribe()` call itself fails (network error on first-run download, decoding failure, etc.) — Task 4's UI catches this to show the error snackbar.

Like Task 2, this wraps native plugins (`record`, `whisper_ggml`) with no pure-Dart branching logic beyond the permission check, and can't be meaningfully unit-tested without a device/mic. No automated test for this task; verify by reading the code. End-to-end behavior is verified manually in Task 5.

- [ ] **Step 1: Write the service**

Create `lib/services/speech_to_text_service.dart`:

```dart
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

abstract class SpeechToTextService {
  Future<void> startRecording();
  Future<String?> stopRecordingAndTranscribe();
}

class WhisperSpeechToTextService implements SpeechToTextService {
  WhisperSpeechToTextService({
    AudioRecorder? recorder,
    WhisperController? controller,
  })  : _recorder = recorder ?? AudioRecorder(),
        _controller = controller ?? WhisperController();

  final AudioRecorder _recorder;
  final WhisperController _controller;

  @override
  Future<void> startRecording() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission denied');
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_demo_recording.wav';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
  }

  @override
  Future<String?> stopRecordingAndTranscribe() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    final result = await _controller.transcribe(
      model: WhisperModel.base,
      audioPath: path,
      lang: 'en',
    );
    return result?.transcription.text;
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/services/speech_to_text_service.dart
git commit -m "feat: add SpeechToTextService wrapping whisper_ggml and record"
```

---

### Task 4: Voice demo screen

**Files:**
- Create: `lib/screens/voice_demo_screen.dart`
- Test: `test/screens/voice_demo_screen_test.dart`

**Interfaces:**
- Consumes: `SpeechToTextService` (`startRecording()`, `stopRecordingAndTranscribe()`) from Task 3, `TextToSpeechService` (`speak(String)`, `stop()`) from Task 2, and `openAppSettings()` from the `permission_handler` package (Task 1).
- Produces: `class VoiceDemoScreen extends StatefulWidget` with constructor `VoiceDemoScreen({super.key, SpeechToTextService? sttService, TextToSpeechService? ttsService})`, importable from `package:wishper_flow_rnd/screens/voice_demo_screen.dart`. Task 5 imports this and instantiates it with no arguments (real services).
- Uses widget `Key`s `'mic_button'`, `'transcript_field'`, `'speak_field'`, `'speak_button'`, `'open_settings_button'` — later tasks/tests may rely on these.

- [ ] **Step 1: Write the failing widget tests**

Create `test/screens/voice_demo_screen_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishper_flow_rnd/screens/voice_demo_screen.dart';
import 'package:wishper_flow_rnd/services/speech_to_text_service.dart';
import 'package:wishper_flow_rnd/services/text_to_speech_service.dart';

class FakeSttService implements SpeechToTextService {
  bool startRecordingCalled = false;
  bool throwOnStart = false;
  bool throwOnStop = false;
  bool useCompleter = false;
  String? transcriptToReturn = 'hello world';
  final Completer<String?> _transcribeCompleter = Completer<String?>();

  @override
  Future<void> startRecording() async {
    if (throwOnStart) throw StateError('Microphone permission denied');
    startRecordingCalled = true;
  }

  @override
  Future<String?> stopRecordingAndTranscribe() async {
    if (throwOnStop) throw StateError('Transcription failed');
    if (useCompleter) return _transcribeCompleter.future;
    return transcriptToReturn;
  }

  void completeTranscription(String? text) {
    _transcribeCompleter.complete(text);
  }
}

class FakeTtsService implements TextToSpeechService {
  String? lastSpokenText;

  @override
  Future<void> speak(String text) async {
    lastSpokenText = text;
  }

  @override
  Future<void> stop() async {}
}

void main() {
  testWidgets('idle state shows mic icon and disabled speak button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VoiceDemoScreen(
          sttService: FakeSttService(),
          ttsService: FakeTtsService(),
        ),
      ),
    );

    expect(find.byIcon(Icons.mic), findsOneWidget);
    final speakButton = tester.widget<ElevatedButton>(
      find.byKey(const Key('speak_button')),
    );
    expect(speakButton.onPressed, isNull);
  });

  testWidgets('tapping mic starts recording and shows stop icon', (
    tester,
  ) async {
    final stt = FakeSttService();
    await tester.pumpWidget(
      MaterialApp(
        home: VoiceDemoScreen(sttService: stt, ttsService: FakeTtsService()),
      ),
    );

    await tester.tap(find.byKey(const Key('mic_button')));
    await tester.pump();

    expect(stt.startRecordingCalled, isTrue);
    expect(find.byIcon(Icons.stop), findsOneWidget);
  });

  testWidgets('stopping recording shows a spinner then populates the transcript', (
    tester,
  ) async {
    final stt = FakeSttService()..useCompleter = true;
    await tester.pumpWidget(
      MaterialApp(
        home: VoiceDemoScreen(sttService: stt, ttsService: FakeTtsService()),
      ),
    );

    await tester.tap(find.byKey(const Key('mic_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mic_button')));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.text(
        'First use sets up the speech model — this may take a bit longer',
      ),
      findsOneWidget,
    );

    stt.completeTranscription('hello world');
    await tester.pumpAndSettle();

    final transcriptField = tester.widget<TextField>(
      find.byKey(const Key('transcript_field')),
    );
    expect(transcriptField.controller?.text, 'hello world');
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('mic permission error shows an explanatory dialog', (
    tester,
  ) async {
    final stt = FakeSttService()..throwOnStart = true;
    await tester.pumpWidget(
      MaterialApp(
        home: VoiceDemoScreen(sttService: stt, ttsService: FakeTtsService()),
      ),
    );

    await tester.tap(find.byKey(const Key('mic_button')));
    await tester.pumpAndSettle();

    expect(find.text('Microphone permission needed'), findsOneWidget);
    // Present but not tapped — tapping calls the real permission_handler
    // plugin, which has no test-environment implementation.
    expect(find.byKey(const Key('open_settings_button')), findsOneWidget);
  });

  testWidgets('transcription failure shows an error snackbar', (
    tester,
  ) async {
    final stt = FakeSttService()..throwOnStop = true;
    await tester.pumpWidget(
      MaterialApp(
        home: VoiceDemoScreen(sttService: stt, ttsService: FakeTtsService()),
      ),
    );

    await tester.tap(find.byKey(const Key('mic_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mic_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not transcribe audio. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('typing text enables the speak button and calls the tts service', (
    tester,
  ) async {
    final tts = FakeTtsService();
    await tester.pumpWidget(
      MaterialApp(
        home: VoiceDemoScreen(sttService: FakeSttService(), ttsService: tts),
      ),
    );

    await tester.enterText(find.byKey(const Key('speak_field')), 'hi there');
    await tester.pump();

    final speakButton = tester.widget<ElevatedButton>(
      find.byKey(const Key('speak_button')),
    );
    expect(speakButton.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('speak_button')));
    await tester.pump();

    expect(tts.lastSpokenText, 'hi there');
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/screens/voice_demo_screen_test.dart`
Expected: FAIL — compile error, `voice_demo_screen.dart` doesn't exist yet.

- [ ] **Step 3: Write the screen**

Create `lib/screens/voice_demo_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../services/speech_to_text_service.dart';
import '../services/text_to_speech_service.dart';

enum _SttStatus { idle, recording, transcribing }

class VoiceDemoScreen extends StatefulWidget {
  VoiceDemoScreen({super.key, SpeechToTextService? sttService, TextToSpeechService? ttsService})
      : sttService = sttService ?? WhisperSpeechToTextService(),
        ttsService = ttsService ?? FlutterTextToSpeechService();

  final SpeechToTextService sttService;
  final TextToSpeechService ttsService;

  @override
  State<VoiceDemoScreen> createState() => _VoiceDemoScreenState();
}

class _VoiceDemoScreenState extends State<VoiceDemoScreen> {
  _SttStatus _sttStatus = _SttStatus.idle;
  bool _isFirstTranscription = true;
  final _transcriptController = TextEditingController();
  final _speakController = TextEditingController();

  @override
  void dispose() {
    _transcriptController.dispose();
    _speakController.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_sttStatus == _SttStatus.recording) {
      setState(() => _sttStatus = _SttStatus.transcribing);
      try {
        final text = await widget.sttService.stopRecordingAndTranscribe();
        setState(() {
          _transcriptController.text = text ?? '';
          _sttStatus = _SttStatus.idle;
          _isFirstTranscription = false;
        });
      } catch (_) {
        setState(() => _sttStatus = _SttStatus.idle);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not transcribe audio. Please try again.'),
          ),
        );
      }
      return;
    }

    try {
      await widget.sttService.startRecording();
      setState(() => _sttStatus = _SttStatus.recording);
    } catch (_) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Microphone permission needed'),
          content: const Text(
            'This demo needs microphone access to record your voice. '
            'Please enable it in Settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Not now'),
            ),
            TextButton(
              key: const Key('open_settings_button'),
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _speak() async {
    final text = _speakController.text.trim();
    if (text.isEmpty) return;
    await widget.ttsService.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    final isTranscribing = _sttStatus == _SttStatus.transcribing;
    final canSpeak = _speakController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Voice Demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Speech to text', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            key: const Key('transcript_field'),
            controller: _transcriptController,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Your transcribed speech will appear here',
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                IconButton.filled(
                  key: const Key('mic_button'),
                  onPressed: isTranscribing ? null : _toggleRecording,
                  icon: Icon(
                    _sttStatus == _SttStatus.recording ? Icons.stop : Icons.mic,
                  ),
                ),
                if (isTranscribing) ...[
                  const SizedBox(height: 8),
                  const CircularProgressIndicator(),
                  if (_isFirstTranscription) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'First use sets up the speech model — this may take a bit longer',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text('Text to speech', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            key: const Key('speak_field'),
            controller: _speakController,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Type text to have it spoken aloud',
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: ElevatedButton.icon(
              key: const Key('speak_button'),
              onPressed: canSpeak ? _speak : null,
              icon: const Icon(Icons.volume_up),
              label: const Text('Speak'),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/screens/voice_demo_screen_test.dart`
Expected: all 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/voice_demo_screen.dart test/screens/voice_demo_screen_test.dart
git commit -m "feat: add VoiceDemoScreen with widget tests against fake services"
```

---

### Task 5: Wire up main.dart

**Files:**
- Modify: `lib/main.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: `VoiceDemoScreen` (no-argument constructor) from Task 4.

- [ ] **Step 1: Write the failing smoke test**

Replace the contents of `test/widget_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wishper_flow_rnd/main.dart';

void main() {
  testWidgets('App loads the voice demo screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Voice Demo'), findsOneWidget);
    expect(find.text('Speech to text'), findsOneWidget);
    expect(find.text('Text to speech'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/widget_test.dart`
Expected: FAIL — `main.dart` still shows the counter screen, so `find.text('Voice Demo')` finds nothing.

- [ ] **Step 3: Update `main.dart` to launch `VoiceDemoScreen`**

Replace the entire contents of `lib/main.dart`:

```dart
import 'package:flutter/material.dart';

import 'screens/voice_demo_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: VoiceDemoScreen(),
    );
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/widget_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`
Expected: all tests PASS (both `test/widget_test.dart` and `test/screens/voice_demo_screen_test.dart`).

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart test/widget_test.dart
git commit -m "feat: launch VoiceDemoScreen from main.dart"
```

- [ ] **Step 7: Manual on-device verification**

Automated tests can't exercise the real `whisper_ggml`/`record`/`flutter_tts` plugins. Run the app on a real device or an Android emulator (not the iOS simulator — it has no mic input):

Run: `flutter run`

Check by hand:
1. Tap the mic button, speak a sentence, tap it again to stop. First run should show the "First use sets up the speech model" hint and take noticeably longer (model download); the transcript field should then show reasonably accurate text.
2. Deny the mic permission (or run on a fresh install and tap "Don't Allow") — the permission dialog should appear.
3. Type a sentence in the text-to-speech field and tap "Speak" — it should be spoken aloud through the device's TTS voice.
