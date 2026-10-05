import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/clock.dart';
import '../../domain/audio/audio_recording.dart';
import '../../domain/match/match_event.dart';
import '../../domain/repositories/audio_repository.dart';
import '../db/app_database.dart';

class DriftAudioRepository implements AudioRepository {
  DriftAudioRepository(this.db, {this.clock = const SystemClock()});

  final AppDatabase db;
  final Clock clock;

  int get _now => clock.now().millisecondsSinceEpoch;

  @override
  Future<void> save(AudioRecording r) =>
      db.into(db.audioRecordings).insertOnConflictUpdate(AudioRecordingsCompanion(
            id: Value(r.id),
            matchId: Value(r.matchId),
            eventId: Value(r.eventId),
            mimeType: Value(r.mimeType),
            durationMs: Value(r.duration.inMilliseconds),
            sizeBytes: Value(r.sizeBytes),
            bytes: Value(r.bytes),
            createdAt: Value(r.createdAt.millisecondsSinceEpoch),
            updatedAt: Value(r.updatedAt.millisecondsSinceEpoch),
            transcriptStatus: Value(r.transcriptStatus.code),
            attempts: Value(r.attempts),
            lastError: Value(r.lastError),
            revision: Value(r.revision),
            syncStatus: Value(r.syncStatus.code),
            deletedAt: Value(r.deletedAt?.millisecondsSinceEpoch),
          ));

  @override
  Future<AudioRecording?> get(String id, {bool withBytes = true}) async {
    final row = await (db.select(db.audioRecordings)
          ..where((a) => a.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _fromRow(row, withBytes: withBytes);
  }

  @override
  Stream<List<AudioRecording>> watchByMatch(String matchId) =>
      (db.select(db.audioRecordings)
            ..where((a) => a.matchId.equals(matchId))
            ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
          .watch()
          .map((rows) =>
              rows.map((r) => _fromRow(r, withBytes: false)).toList());

  @override
  Future<List<AudioRecording>> pendingTranscriptions({int limit = 20}) async {
    final rows = await (db.select(db.audioRecordings)
          ..where((a) =>
              a.transcriptStatus.equals(TranscriptStatus.pending.code) &
              a.deletedAt.isNull() &
              a.bytes.isNotNull())
          ..orderBy([(a) => OrderingTerm.asc(a.createdAt)])
          ..limit(limit))
        .get();
    return rows.map((r) => _fromRow(r, withBytes: false)).toList();
  }

  @override
  Future<void> saveTranscript(String recordingId, String transcript) =>
      db.transaction(() async {
        final rec = await (db.select(db.audioRecordings)
              ..where((a) => a.id.equals(recordingId)))
            .getSingle();
        final now = _now;
        await (db.update(db.audioRecordings)
              ..where((a) => a.id.equals(recordingId)))
            .write(AudioRecordingsCompanion(
          transcriptStatus: Value(TranscriptStatus.done.code),
          lastError: const Value(null),
          updatedAt: Value(now),
          revision: Value(rec.revision + 1),
          syncStatus: Value(SyncStatus.pending.code),
        ));
        final ev = await (db.select(db.matchEvents)
              ..where((e) => e.id.equals(rec.eventId)))
            .getSingleOrNull();
        if (ev == null) return;
        final meta = _decode(ev.metadataJson);
        // Never overwrite a text the user already typed by hand.
        final existing = meta[MetaKeys.text] as String?;
        if (existing == null || existing.trim().isEmpty) {
          meta[MetaKeys.text] = transcript;
        }
        meta[MetaKeys.transcriptStatus] = TranscriptStatus.done.code;
        await (db.update(db.matchEvents)..where((e) => e.id.equals(ev.id)))
            .write(MatchEventsCompanion(
          metadataJson: Value(jsonEncode(meta)),
          updatedAt: Value(now),
          revision: Value(ev.revision + 1),
          syncStatus: Value(SyncStatus.pending.code),
        ));
      });

  @override
  Future<void> markTranscriptionError(String recordingId, String error,
          {int maxAttempts = 5}) =>
      db.transaction(() async {
        final rec = await (db.select(db.audioRecordings)
              ..where((a) => a.id.equals(recordingId)))
            .getSingle();
        final attempts = rec.attempts + 1;
        await (db.update(db.audioRecordings)
              ..where((a) => a.id.equals(recordingId)))
            .write(AudioRecordingsCompanion(
          attempts: Value(attempts),
          lastError: Value(error),
          transcriptStatus: Value(attempts >= maxAttempts
              ? TranscriptStatus.failed.code
              : TranscriptStatus.pending.code),
          updatedAt: Value(_now),
        ));
      });

  @override
  Future<void> deleteAudio(String recordingId) => db.transaction(() async {
        final rec = await (db.select(db.audioRecordings)
              ..where((a) => a.id.equals(recordingId)))
            .getSingleOrNull();
        if (rec == null) return;
        await (db.update(db.audioRecordings)
              ..where((a) => a.id.equals(recordingId)))
            .write(AudioRecordingsCompanion(
          bytes: const Value(null),
          deletedAt: Value(_now),
          updatedAt: Value(_now),
          revision: Value(rec.revision + 1),
          syncStatus: Value(SyncStatus.pending.code),
        ));
      });

  static Map<String, dynamic> _decode(String json) {
    try {
      final v = jsonDecode(json);
      return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static DateTime _dt(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

  static AudioRecording _fromRow(AudioRow r, {required bool withBytes}) =>
      AudioRecording(
        id: r.id,
        matchId: r.matchId,
        eventId: r.eventId,
        mimeType: r.mimeType,
        duration: Duration(milliseconds: r.durationMs),
        sizeBytes: r.sizeBytes,
        bytes: withBytes ? r.bytes : null,
        createdAt: _dt(r.createdAt),
        updatedAt: _dt(r.updatedAt),
        transcriptStatus: TranscriptStatus.fromCode(r.transcriptStatus),
        attempts: r.attempts,
        lastError: r.lastError,
        revision: r.revision,
        syncStatus: SyncStatus.fromCode(r.syncStatus),
        deletedAt: r.deletedAt == null ? null : _dt(r.deletedAt!),
      );
}
