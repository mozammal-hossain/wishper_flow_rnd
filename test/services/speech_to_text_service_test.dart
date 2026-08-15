import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:whisper_ggml/whisper_ggml.dart';
// TranscribeResult isn't re-exported by the public whisper_ggml barrel file.
import 'package:whisper_ggml/src/models/whisper_result.dart';
import 'package:wishper_flow_rnd/services/speech_to_text_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => '/tmp';
}

class _FakeRecordPlatform implements RecordPlatform {
  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      true;

  @override
  Future<void> start(String recorderId, RecordConfig config,
          {required String path}) async =>
      {};

  @override
  Future<String?> stop(String recorderId) async =>
      '/tmp/voice_demo_recording.wav';

  @override
  Stream<RecordState> onStateChanged(String recorderId) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWhisperController implements WhisperController {
  final List<String> calls = [];
  String? lastTranscribeLang;

  @override
  Future<String> downloadModel(WhisperModel model) async {
    calls.add('downloadModel');
    return 'fake/model/path';
  }

  @override
  Future<TranscribeResult?> transcribe({
    required WhisperModel model,
    required String audioPath,
    String lang = 'en',
    bool diarize = false,
    String? initialPrompt,
    bool noContext = false,
    bool suppressNonSpeechTokens = false,
    bool withSegments = false,
    bool splitOnWord = false,
    bool keepModelLoaded = false,
    void Function(int percent)? onProgress,
  }) async {
    calls.add('transcribe');
    lastTranscribeLang = lang;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'stopRecordingAndTranscribe downloads the model before transcribing',
      () async {
    PathProviderPlatform.instance = _FakePathProviderPlatform();
    RecordPlatform.instance = _FakeRecordPlatform();
    final fakeController = _FakeWhisperController();
    final service = WhisperSpeechToTextService(controller: fakeController);

    await service.startRecording();
    await service.stopRecordingAndTranscribe();

    expect(fakeController.calls, ['downloadModel', 'transcribe']);
  });

  test(
      'stopRecordingAndTranscribe lets Whisper auto-detect the spoken language',
      () async {
    PathProviderPlatform.instance = _FakePathProviderPlatform();
    RecordPlatform.instance = _FakeRecordPlatform();
    final fakeController = _FakeWhisperController();
    final service = WhisperSpeechToTextService(controller: fakeController);

    await service.startRecording();
    await service.stopRecordingAndTranscribe();

    expect(fakeController.lastTranscribeLang, 'auto');
  });
}
