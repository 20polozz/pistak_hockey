import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Plays a stored voice incident (WAV bytes) on Android and Web.
class AudioPlaybackService {
  AudioPlayer? _player;

  Future<void> play(Uint8List bytes, {String mimeType = 'audio/wav'}) async {
    await stop();
    final p = AudioPlayer();
    _player = p;
    await p.play(BytesSource(bytes, mimeType: mimeType));
  }

  Future<void> stop() async {
    final p = _player;
    _player = null;
    if (p != null) {
      await p.stop();
      await p.dispose();
    }
  }
}
