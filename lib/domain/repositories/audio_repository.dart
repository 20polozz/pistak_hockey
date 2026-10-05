import '../audio/audio_recording.dart';

/// Local storage of voice-incident audio and its transcription state.
abstract class AudioRepository {
  Future<void> save(AudioRecording recording);
  Future<AudioRecording?> get(String id, {bool withBytes = true});
  Stream<List<AudioRecording>> watchByMatch(String matchId);

  /// Recordings whose transcription is still pending (oldest first).
  Future<List<AudioRecording>> pendingTranscriptions({int limit = 20});

  /// Stores the transcript as the editable text of the incident event and
  /// marks the recording as transcribed — atomically.
  Future<void> saveTranscript(String recordingId, String transcript);

  /// Records a failed attempt; after [maxAttempts] the status becomes failed.
  Future<void> markTranscriptionError(String recordingId, String error,
      {int maxAttempts = 5});

  /// Privacy: removes the audio bytes, keeps the incident and its text.
  Future<void> deleteAudio(String recordingId);
}
