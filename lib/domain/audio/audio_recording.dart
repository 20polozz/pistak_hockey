import 'dart:typed_data';

import '../match/match_event.dart';

/// Lifecycle of the Speech-to-Text of a voice incident. Transcription is
/// fully decoupled from the match: a recording can stay [pending] forever and
/// the match is still complete.
enum TranscriptStatus {
  /// Waiting for a transcription service / connection.
  pending,

  /// Transcribed; text stored in the incident event.
  done,

  /// Gave up after several errors (the audio is kept).
  failed;

  String get code => name;

  static TranscriptStatus fromCode(String? code) => switch (code) {
        'done' => TranscriptStatus.done,
        'failed' => TranscriptStatus.failed,
        _ => TranscriptStatus.pending,
      };
}

/// Audio of a voice incident, stored locally (bytes in the local database on
/// every platform). [bytes] is null once the user deletes the audio.
class AudioRecording {
  const AudioRecording({
    required this.id,
    required this.matchId,
    required this.eventId,
    required this.mimeType,
    required this.duration,
    required this.sizeBytes,
    this.bytes,
    required this.createdAt,
    required this.updatedAt,
    this.transcriptStatus = TranscriptStatus.pending,
    this.attempts = 0,
    this.lastError,
    this.revision = 1,
    this.syncStatus = SyncStatus.pending,
    this.deletedAt,
  });

  final String id;
  final String matchId;
  final String eventId;
  final String mimeType;
  final Duration duration;
  final int sizeBytes;
  final Uint8List? bytes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final TranscriptStatus transcriptStatus;
  final int attempts;
  final String? lastError;
  final int revision;
  final SyncStatus syncStatus;
  final DateTime? deletedAt;

  bool get hasAudio => bytes != null && deletedAt == null;
}
