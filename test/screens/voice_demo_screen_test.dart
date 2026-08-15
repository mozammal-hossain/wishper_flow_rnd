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
