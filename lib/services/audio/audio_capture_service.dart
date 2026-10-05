import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../../core/wav.dart';

class CapturedAudio {
  const CapturedAudio(this.wav, this.duration);
  final Uint8List wav;
  final Duration duration;
  String get mimeType => 'audio/wav';
}

class MicrophoneUnavailable implements Exception {
  const MicrophoneUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'MicrophoneUnavailable($reason)';
}

/// Records a voice incident as PCM 16-bit mono and returns it as WAV bytes.
///
/// Streaming PCM works the same on Android and Web (no temp files, no blob
/// URLs), and the result is stored directly in the local database.
class AudioCaptureService {
  AudioCaptureService();

  static const sampleRate = 16000; // speech quality, ~32 KB/s
  static const channels = 1;

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _sub;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  Completer<void>? _streamDone;

  bool get isRecording => _recorder != null;

  /// Asks for microphone permission (only when the user starts recording).
  Future<void> start() async {
    if (_recorder != null) return;
    final rec = AudioRecorder();
    try {
      if (!await rec.hasPermission()) {
        throw const MicrophoneUnavailable('permission denied');
      }
      _buffer.clear();
      final stream = await rec.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: channels,
      ));
      _streamDone = Completer<void>();
      _sub = stream.listen(
        _buffer.add,
        onDone: () => _streamDone?.complete(),
        onError: (Object _) => _streamDone?.complete(),
        cancelOnError: true,
      );
      _recorder = rec;
    } catch (e) {
      await rec.dispose();
      if (e is MicrophoneUnavailable) rethrow;
      throw MicrophoneUnavailable('$e');
    }
  }

  /// Stops and returns the recording (WAV).
  Future<CapturedAudio> stop() async {
    final rec = _recorder;
    if (rec == null) throw const MicrophoneUnavailable('not recording');
    await rec.stop();
    // The stream close event delivers the last chunk.
    await _streamDone?.future.timeout(const Duration(seconds: 2),
        onTimeout: () {});
    await _sub?.cancel();
    await rec.dispose();
    _recorder = null;
    final pcm = _buffer.takeBytes();
    return CapturedAudio(
      pcm16ToWav(pcm, sampleRate: sampleRate, channels: channels),
      pcm16Duration(pcm.length, sampleRate: sampleRate, channels: channels),
    );
  }

  Future<void> cancel() async {
    final rec = _recorder;
    _recorder = null;
    await _sub?.cancel();
    if (rec != null) {
      await rec.cancel();
      await rec.dispose();
    }
    _buffer.clear();
  }
}
