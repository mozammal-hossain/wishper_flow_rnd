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
    // downloadModel no-ops once the model file is already on disk, so this
    // is cheap on every call after the first.
    await _controller.downloadModel(WhisperModel.base);
    final result = await _controller.transcribe(
      model: WhisperModel.base,
      audioPath: path,
      lang: 'auto',
    );
    return result?.transcription.text;
  }
}
