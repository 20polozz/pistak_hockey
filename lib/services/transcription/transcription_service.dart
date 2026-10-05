import 'dart:typed_data';

/// Speech-to-Text boundary. The real implementation (Phase 4) will call the
/// PISTAK backend, which holds the provider API key — never the app.
abstract class TranscriptionService {
  /// False when there is no configured service or no connectivity.
  Future<bool> isAvailable();

  /// Returns the transcript. Throws [TranscriptionUnavailable] for transient
  /// problems (offline, server down) and any other error for real failures.
  Future<String> transcribe(Uint8List audio,
      {required String mimeType, String? languageCode});
}

class TranscriptionUnavailable implements Exception {
  const TranscriptionUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'TranscriptionUnavailable($reason)';
}

/// Phase 1: no Speech-to-Text configured. Recordings stay pending.
class NoTranscriptionService implements TranscriptionService {
  const NoTranscriptionService();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<String> transcribe(Uint8List audio,
          {required String mimeType, String? languageCode}) =>
      throw const TranscriptionUnavailable('no transcription service');
}
