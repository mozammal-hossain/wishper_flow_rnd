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
