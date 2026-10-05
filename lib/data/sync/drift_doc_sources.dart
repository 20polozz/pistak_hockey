import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/match/match_event.dart';
import '../../sync/doc_source.dart';
import '../db/app_database.dart';

/// Marks rows synced only if they still have the acknowledged revision
/// (an edit made while the push was in flight stays pending).
Future<void> _markSynced(AppDatabase db, TableInfo<Table, dynamic> table,
    Map<String, int> accepted) async {
  if (accepted.isEmpty) return;
  await db.transaction(() async {
    for (final e in accepted.entries) {
      await db.customUpdate(
        'UPDATE ${table.actualTableName} SET sync_status = ? '
        'WHERE id = ? AND revision = ?',
        variables: [
          Variable.withString(SyncStatus.synced.code),
          Variable.withString(e.key),
          Variable.withInt(e.value),
        ],
        updates: {table},
      );
    }
  });
}

/// Remote wins only if it is newer AND there is no local pending change.
bool _skip(int? localRevision, String? localStatus, int remoteRevision) =>
    localRevision != null &&
    (localRevision >= remoteRevision || localStatus == SyncStatus.pending.code);

int _int(Object? v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;
int? _intOrNull(Object? v) => (v as num?)?.toInt();
String? _str(Object? v) => v as String?;

class TeamDocSource implements DocSyncSource {
  TeamDocSource(this.db);
  final AppDatabase db;

  @override
  String get key => 'teams';

  /// Crests travel inside the document (base64): keep batches small.
  @override
  int get batchSize => 20;

  @override
  Future<List<Map<String, dynamic>>> pending({required int limit}) async {
    final rows = await (db.select(db.teams)
          ..where((t) => t.syncStatus.equals(SyncStatus.pending.code))
          ..orderBy([(t) => OrderingTerm.asc(t.updatedAt)])
          ..limit(limit))
        .get();
    return [
      for (final r in rows)
        {
          'id': r.id,
          'name': r.name,
          'shortName': r.shortName,
          'category': r.category,
          'season': r.season,
          'crest': r.crest == null ? null : base64Encode(r.crest!),
          'createdAt': r.createdAt,
          'updatedAt': r.updatedAt,
          'revision': r.revision,
          'deletedAt': r.deletedAt,
        }
    ];
  }

  @override
  Future<void> markSynced(Map<String, int> accepted) =>
      _markSynced(db, db.teams, accepted);

  @override
  Future<int> applyRemote(List<Map<String, dynamic>> docs) =>
      db.transaction(() async {
        var n = 0;
        for (final d in docs) {
          final id = _str(d['id']);
          if (id == null) continue;
          final rev = _int(d['revision'], 1);
          final cur = await (db.select(db.teams)..where((t) => t.id.equals(id)))
              .getSingleOrNull();
          if (_skip(cur?.revision, cur?.syncStatus, rev)) continue;
          final crest = _str(d['crest']);
          await db.into(db.teams).insertOnConflictUpdate(TeamsCompanion(
                id: Value(id),
                name: Value(_str(d['name']) ?? ''),
                shortName: Value(_str(d['shortName'])),
                category: Value(_str(d['category'])),
                season: Value(_str(d['season'])),
                crest: Value(crest == null ? null : base64Decode(crest)),
                createdAt: Value(_int(d['createdAt'])),
                updatedAt: Value(_int(d['updatedAt'])),
                revision: Value(rev),
                syncStatus: Value(SyncStatus.synced.code),
                deletedAt: Value(_intOrNull(d['deletedAt'])),
              ));
          n++;
        }
        return n;
      });
}

class MemberDocSource implements DocSyncSource {
  MemberDocSource(this.db);
  final AppDatabase db;

  @override
  String get key => 'members';

  @override
  int get batchSize => 100;

  @override
  Future<List<Map<String, dynamic>>> pending({required int limit}) async {
    final rows = await (db.select(db.teamMembers)
          ..where((t) => t.syncStatus.equals(SyncStatus.pending.code))
          ..orderBy([(t) => OrderingTerm.asc(t.updatedAt)])
          ..limit(limit))
        .get();
    return [
      for (final r in rows)
        {
          'id': r.id,
          'teamId': r.teamId,
          'role': r.role,
          'name': r.name,
          'number': r.number,
          'position': r.position,
          'notes': r.notes,
          'createdAt': r.createdAt,
          'updatedAt': r.updatedAt,
          'revision': r.revision,
          'deletedAt': r.deletedAt,
        }
    ];
  }

  @override
  Future<void> markSynced(Map<String, int> accepted) =>
      _markSynced(db, db.teamMembers, accepted);

  @override
  Future<int> applyRemote(List<Map<String, dynamic>> docs) =>
      db.transaction(() async {
        var n = 0;
        for (final d in docs) {
          final id = _str(d['id']);
          final teamId = _str(d['teamId']);
          if (id == null || teamId == null) continue;
          final rev = _int(d['revision'], 1);
          final cur = await (db.select(db.teamMembers)
                ..where((t) => t.id.equals(id)))
              .getSingleOrNull();
          if (_skip(cur?.revision, cur?.syncStatus, rev)) continue;
          await db.into(db.teamMembers).insertOnConflictUpdate(
                TeamMembersCompanion(
                  id: Value(id),
                  teamId: Value(teamId),
                  role: Value(_str(d['role']) ?? 'player'),
                  name: Value(_str(d['name']) ?? ''),
                  number: Value(_intOrNull(d['number'])),
                  position: Value(_str(d['position'])),
                  notes: Value(_str(d['notes'])),
                  createdAt: Value(_int(d['createdAt'])),
                  updatedAt: Value(_int(d['updatedAt'])),
                  revision: Value(rev),
                  syncStatus: Value(SyncStatus.synced.code),
                  deletedAt: Value(_intOrNull(d['deletedAt'])),
                ),
              );
          n++;
        }
        return n;
      });
}

/// Voice-incident audio: metadata as a document, bytes as a separate file.
class AudioDocSource implements BlobDocSource {
  AudioDocSource(this.db);
  final AppDatabase db;

  @override
  String get key => 'audio';

  @override
  int get batchSize => 10;

  @override
  Future<List<Map<String, dynamic>>> pending({required int limit}) async {
    final rows = await (db.select(db.audioRecordings)
          ..where((a) => a.syncStatus.equals(SyncStatus.pending.code))
          ..orderBy([(a) => OrderingTerm.asc(a.createdAt)])
          ..limit(limit))
        .get();
    return [
      for (final r in rows)
        {
          'id': r.id,
          'matchId': r.matchId,
          'eventId': r.eventId,
          'mimeType': r.mimeType,
          'durationMs': r.durationMs,
          'sizeBytes': r.sizeBytes,
          'createdAt': r.createdAt,
          'updatedAt': r.updatedAt,
          'transcriptStatus': r.transcriptStatus,
          'revision': r.revision,
          'deletedAt': r.deletedAt,
          // false once the user removed the audio (privacy): the server
          // deletes its copy too.
          'hasAudio': r.deletedAt == null,
        }
    ];
  }

  @override
  Future<void> markSynced(Map<String, int> accepted) =>
      _markSynced(db, db.audioRecordings, accepted);

  @override
  Future<({Uint8List bytes, String mimeType})?> blobFor(String id) async {
    final r = await (db.select(db.audioRecordings)
          ..where((a) => a.id.equals(id)))
        .getSingleOrNull();
    if (r == null || r.bytes == null || r.deletedAt != null) return null;
    return (bytes: r.bytes!, mimeType: r.mimeType);
  }

  @override
  Future<int> applyRemote(List<Map<String, dynamic>> docs) =>
      db.transaction(() async {
        var n = 0;
        for (final d in docs) {
          final id = _str(d['id']);
          final matchId = _str(d['matchId']);
          final eventId = _str(d['eventId']);
          if (id == null || matchId == null || eventId == null) continue;
          final rev = _int(d['revision'], 1);
          final cur = await (db.select(db.audioRecordings)
                ..where((a) => a.id.equals(id)))
              .getSingleOrNull();
          if (_skip(cur?.revision, cur?.syncStatus, rev)) continue;
          final removed = d['hasAudio'] == false;
          await db.into(db.audioRecordings).insertOnConflictUpdate(
                AudioRecordingsCompanion(
                  id: Value(id),
                  matchId: Value(matchId),
                  eventId: Value(eventId),
                  mimeType: Value(_str(d['mimeType']) ?? 'audio/wav'),
                  durationMs: Value(_int(d['durationMs'])),
                  sizeBytes: Value(_int(d['sizeBytes'])),
                  createdAt: Value(_int(d['createdAt'])),
                  updatedAt: Value(_int(d['updatedAt'])),
                  transcriptStatus:
                      Value(_str(d['transcriptStatus']) ?? 'pending'),
                  revision: Value(rev),
                  syncStatus: Value(SyncStatus.synced.code),
                  deletedAt: Value(_intOrNull(d['deletedAt'])),
                  // Bytes are kept if we already have them; removed if the
                  // audio was deleted on another device.
                  bytes: removed ? const Value(null) : const Value.absent(),
                ),
              );
          n++;
        }
        return n;
      });

  @override
  Future<List<String>> missingBlobs({int limit = 10}) async {
    final rows = await (db.select(db.audioRecordings)
          ..where((a) =>
              a.bytes.isNull() &
              a.deletedAt.isNull() &
              a.sizeBytes.isBiggerThanValue(0))
          ..orderBy([(a) => OrderingTerm.desc(a.createdAt)])
          ..limit(limit))
        .get();
    return [for (final r in rows) r.id];
  }

  @override
  Future<void> saveBlob(String id, Uint8List bytes) =>
      (db.update(db.audioRecordings)
            ..where((a) => a.id.equals(id) & a.bytes.isNull()))
          .write(AudioRecordingsCompanion(bytes: Value(bytes)));
}
