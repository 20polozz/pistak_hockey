import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/clock.dart';
import '../../core/ids.dart';
import '../../domain/match/match_event.dart';
import '../../domain/match/match_info.dart';
import '../../domain/match/match_projector.dart';
import '../../domain/repositories/match_repository.dart';
import '../../domain/sport/match_format.dart';
import '../db/app_database.dart';

class DriftMatchRepository implements MatchRepository {
  DriftMatchRepository(
    this.db, {
    required this.deviceId,
    this.clock = const SystemClock(),
    this.ids = const UuidV7Generator(),
    this.projector = const MatchProjector(),
  });

  final AppDatabase db;
  final String deviceId;
  final Clock clock;
  final IdGenerator ids;
  final MatchProjector projector;

  int get _nowMs => clock.now().millisecondsSinceEpoch;

  // ================================================================ matches

  @override
  Future<MatchInfo> createMatch({
    required String sport,
    required MatchFormat format,
    String? homeName,
    String? awayName,
    String? homeTeamId,
    String? awayTeamId,
    String? category,
    String? competition,
    String? venue,
    String? season,
    String? notes,
    DateTime? scheduledAt,
  }) async {
    final now = _nowMs;
    final id = ids.newId();
    await db.into(db.matches).insert(MatchesCompanion(
          id: Value(id),
          sport: Value(sport),
          status: Value(MatchStatus.notStarted.code),
          formatJson: Value(jsonEncode(format.toJson())),
          homeName: Value(_clean(homeName)),
          awayName: Value(_clean(awayName)),
          homeTeamId: Value(homeTeamId),
          awayTeamId: Value(awayTeamId),
          category: Value(_clean(category)),
          competition: Value(_clean(competition)),
          venue: Value(_clean(venue)),
          season: Value(_clean(season)),
          notes: Value(_clean(notes)),
          scheduledAt: Value(scheduledAt?.millisecondsSinceEpoch),
          createdAt: Value(now),
          updatedAt: Value(now),
          deviceId: Value(deviceId),
          revision: const Value(1),
          syncStatus: Value(SyncStatus.pending.code),
        ));
    return (await getMatch(id))!;
  }

  @override
  Future<MatchInfo?> getMatch(String id) async {
    final row = await (db.select(db.matches)..where((m) => m.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _matchFromRow(row);
  }

  @override
  Stream<MatchInfo?> watchMatch(String id) =>
      (db.select(db.matches)..where((m) => m.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r == null ? null : _matchFromRow(r));

  @override
  Stream<List<MatchInfo>> watchMatches() => (db.select(db.matches)
        ..where((m) => m.deletedAt.isNull())
        ..orderBy([(m) => OrderingTerm.desc(m.createdAt)]))
      .watch()
      .map((rows) => rows.map(_matchFromRow).toList());

  @override
  Stream<MatchInfo?> watchActiveMatch() => (db.select(db.matches)
        ..where((m) =>
            m.deletedAt.isNull() & m.status.equals(MatchStatus.live.code))
        ..orderBy([(m) => OrderingTerm.desc(m.updatedAt)])
        ..limit(1))
      .watch()
      .map((rows) => rows.isEmpty ? null : _matchFromRow(rows.first));

  @override
  Future<void> saveMatchDetails(MatchInfo info) => db.transaction(() async {
        final current = await (db.select(db.matches)
              ..where((m) => m.id.equals(info.id)))
            .getSingle();
        await (db.update(db.matches)..where((m) => m.id.equals(info.id)))
            .write(MatchesCompanion(
          formatJson: Value(jsonEncode(info.format.toJson())),
          homeName: Value(_clean(info.homeName)),
          awayName: Value(_clean(info.awayName)),
          homeTeamId: Value(info.homeTeamId),
          awayTeamId: Value(info.awayTeamId),
          category: Value(_clean(info.category)),
          competition: Value(_clean(info.competition)),
          venue: Value(_clean(info.venue)),
          season: Value(_clean(info.season)),
          notes: Value(_clean(info.notes)),
          scheduledAt: Value(info.scheduledAt?.millisecondsSinceEpoch),
          updatedAt: Value(_nowMs),
          revision: Value(current.revision + 1),
          syncStatus: Value(SyncStatus.pending.code),
        ));
        await _refreshCache(info.id);
      });

  @override
  Future<void> deleteMatch(String id) => db.transaction(() async {
        final current = await (db.select(db.matches)
              ..where((m) => m.id.equals(id)))
            .getSingleOrNull();
        if (current == null) return;
        await (db.update(db.matches)..where((m) => m.id.equals(id)))
            .write(MatchesCompanion(
          deletedAt: Value(_nowMs),
          updatedAt: Value(_nowMs),
          revision: Value(current.revision + 1),
          syncStatus: Value(SyncStatus.pending.code),
        ));
      });

  // ================================================================= events

  @override
  Future<List<MatchEvent>> getEvents(String matchId) async =>
      (await _eventsQuery(matchId).get()).map(_eventFromRow).toList();

  @override
  Stream<List<MatchEvent>> watchEvents(String matchId) => _eventsQuery(matchId)
      .watch()
      .map((rows) => rows.map(_eventFromRow).toList());

  SimpleSelectStatement<$MatchEventsTable, MatchEventRow> _eventsQuery(
          String matchId) =>
      db.select(db.matchEvents)
        ..where((e) => e.matchId.equals(matchId))
        ..orderBy([
          (e) => OrderingTerm.asc(e.occurredAt),
          (e) => OrderingTerm.asc(e.seq),
        ]);

  @override
  Future<List<MatchEvent>> appendEvents(
      String matchId, List<MatchEvent> events) async {
    if (events.isEmpty) return const [];
    return db.transaction(() async {
      final maxSeq = db.matchEvents.seq.max();
      final query = db.selectOnly(db.matchEvents)
        ..addColumns([maxSeq])
        ..where(db.matchEvents.matchId.equals(matchId));
      final base = await query.map((r) => r.read(maxSeq)).getSingle() ?? 0;

      final stored = <MatchEvent>[];
      var i = 0;
      for (final e in events) {
        if (e.matchId != matchId) {
          throw ArgumentError('Event ${e.id} belongs to ${e.matchId}');
        }
        final s = e.copyWith(seq: base + (++i), syncStatus: SyncStatus.pending);
        // insertOrIgnore: re-delivering the same event id (e.g. from a watch)
        // is a no-op → idempotent locally too.
        await db
            .into(db.matchEvents)
            .insert(_eventToCompanion(s), mode: InsertMode.insertOrIgnore);
        stored.add(s);
      }
      await _refreshCache(matchId);
      return stored;
    });
  }

  @override
  Future<void> updateEvent(MatchEvent event) => db.transaction(() async {
        final current = await (db.select(db.matchEvents)
              ..where((e) => e.id.equals(event.id)))
            .getSingle();
        await (db.update(db.matchEvents)..where((e) => e.id.equals(event.id)))
            .write(MatchEventsCompanion(
          team: Value(event.team?.code),
          subtype: Value(event.subtype),
          matchTimeMs: Value(event.matchTime.inMilliseconds),
          periodTimeMs: Value(event.periodTime.inMilliseconds),
          metadataJson: Value(jsonEncode(event.metadata)),
          updatedAt: Value(_nowMs),
          revision: Value(current.revision + 1),
          syncStatus: Value(SyncStatus.pending.code),
        ));
        await _refreshCache(current.matchId);
      });

  @override
  Future<List<MatchEvent>> undoLastAction(String matchId) =>
      db.transaction(() async {
        final last = await (db.select(db.matchEvents)
              ..where((e) => e.matchId.equals(matchId) & e.voidedAt.isNull())
              ..orderBy([(e) => OrderingTerm.desc(e.seq)])
              ..limit(1))
            .getSingleOrNull();
        if (last == null) return <MatchEvent>[];
        final rows = await (db.select(db.matchEvents)
              ..where((e) =>
                  e.matchId.equals(matchId) &
                  e.actionId.equals(last.actionId) &
                  e.voidedAt.isNull()))
            .get();
        final now = _nowMs;
        for (final r in rows) {
          await (db.update(db.matchEvents)..where((e) => e.id.equals(r.id)))
              .write(MatchEventsCompanion(
            voidedAt: Value(now),
            updatedAt: Value(now),
            revision: Value(r.revision + 1),
            syncStatus: Value(SyncStatus.pending.code),
          ));
        }
        await _refreshCache(matchId);
        return rows.map(_eventFromRow).toList();
      });

  @override
  Future<void> setEventVoided(String eventId, {required bool voided}) =>
      db.transaction(() async {
        final r = await (db.select(db.matchEvents)
              ..where((e) => e.id.equals(eventId)))
            .getSingleOrNull();
        if (r == null || (r.voidedAt != null) == voided) return;
        final now = _nowMs;
        await (db.update(db.matchEvents)..where((e) => e.id.equals(eventId)))
            .write(MatchEventsCompanion(
          voidedAt: Value(voided ? now : null),
          updatedAt: Value(now),
          revision: Value(r.revision + 1),
          syncStatus: Value(SyncStatus.pending.code),
        ));
        await _refreshCache(r.matchId);
      });

  /// Recomputes the match cache (status, score, start/end) from the log.
  /// Must be called inside the same transaction as the event write.
  Future<void> _refreshCache(String matchId) async {
    final row = await (db.select(db.matches)
          ..where((m) => m.id.equals(matchId)))
        .getSingleOrNull();
    if (row == null) return;
    final format = _decodeFormat(row.formatJson);
    final events = (await _eventsQuery(matchId).get()).map(_eventFromRow);
    final st = projector.project(format, events);
    final status = st.isFinished
        ? MatchStatus.finished
        : st.isStarted
            ? MatchStatus.live
            : MatchStatus.notStarted;
    await (db.update(db.matches)..where((m) => m.id.equals(matchId)))
        .write(MatchesCompanion(
      status: Value(status.code),
      homeScore: Value(st.home.goals),
      awayScore: Value(st.away.goals),
      startedAt: Value(st.matchStartedAt?.millisecondsSinceEpoch),
      endedAt: Value(st.matchEndedAt?.millisecondsSinceEpoch),
      updatedAt: Value(_nowMs),
    ));
  }

  // =================================================================== sync

  @override
  Future<List<MatchEvent>> pendingEvents({int limit = 200}) async {
    final rows = await (db.select(db.matchEvents)
          ..where((e) => e.syncStatus.equals(SyncStatus.pending.code))
          ..orderBy([(e) => OrderingTerm.asc(e.updatedAt)])
          ..limit(limit))
        .get();
    return rows.map(_eventFromRow).toList();
  }

  @override
  Future<List<MatchInfo>> pendingMatches({int limit = 50}) async {
    final rows = await (db.select(db.matches)
          ..where((m) => m.syncStatus.equals(SyncStatus.pending.code))
          ..orderBy([(m) => OrderingTerm.asc(m.updatedAt)])
          ..limit(limit))
        .get();
    return rows.map(_matchFromRow).toList();
  }

  @override
  Future<void> markEventsSynced(Map<String, int> revisionsById) =>
      db.transaction(() async {
        for (final entry in revisionsById.entries) {
          // Only if not edited meanwhile (revision unchanged).
          await (db.update(db.matchEvents)
                ..where((e) =>
                    e.id.equals(entry.key) & e.revision.equals(entry.value)))
              .write(MatchEventsCompanion(
                  syncStatus: Value(SyncStatus.synced.code)));
        }
      });

  @override
  Future<void> markMatchesSynced(Map<String, int> revisionsById) =>
      db.transaction(() async {
        for (final entry in revisionsById.entries) {
          await (db.update(db.matches)
                ..where((m) =>
                    m.id.equals(entry.key) & m.revision.equals(entry.value)))
              .write(
                  MatchesCompanion(syncStatus: Value(SyncStatus.synced.code)));
        }
      });

  @override
  Stream<int> watchPendingCount() {
    final count = db.matchEvents.id.count();
    final q = db.selectOnly(db.matchEvents)
      ..addColumns([count])
      ..where(db.matchEvents.syncStatus.equals(SyncStatus.pending.code));
    return q.watchSingle().map((r) => r.read(count) ?? 0);
  }

  @override
  Future<int> applyRemote({
    List<Map<String, dynamic>> matches = const [],
    List<Map<String, dynamic>> events = const [],
  }) =>
      db.transaction(() async {
        var changed = 0;
        final touched = <String>{};
        for (final j in matches) {
          final m = MatchInfo.fromJson(j);
          final cur = await (db.select(db.matches)
                ..where((x) => x.id.equals(m.id)))
              .getSingleOrNull();
          if (cur != null &&
              (cur.revision >= m.revision ||
                  cur.syncStatus == SyncStatus.pending.code)) {
            continue;
          }
          await db.into(db.matches).insertOnConflictUpdate(MatchesCompanion(
                id: Value(m.id),
                sport: Value(m.sport),
                status: Value(m.status.code),
                formatJson: Value(jsonEncode(m.format.toJson())),
                homeName: Value(m.homeName),
                awayName: Value(m.awayName),
                homeTeamId: Value(m.homeTeamId),
                awayTeamId: Value(m.awayTeamId),
                category: Value(m.category),
                competition: Value(m.competition),
                venue: Value(m.venue),
                season: Value(m.season),
                notes: Value(m.notes),
                scheduledAt: Value(m.scheduledAt?.millisecondsSinceEpoch),
                createdAt: Value(m.createdAt.millisecondsSinceEpoch),
                updatedAt: Value(m.updatedAt.millisecondsSinceEpoch),
                deviceId: Value(m.deviceId),
                revision: Value(m.revision),
                syncStatus: Value(SyncStatus.synced.code),
                deletedAt: Value(m.deletedAt?.millisecondsSinceEpoch),
              ));
          touched.add(m.id);
          changed++;
        }
        for (final j in events) {
          final e = MatchEvent.fromJson(j);
          final cur = await (db.select(db.matchEvents)
                ..where((x) => x.id.equals(e.id)))
              .getSingleOrNull();
          if (cur != null &&
              (cur.revision >= e.revision ||
                  cur.syncStatus == SyncStatus.pending.code)) {
            continue;
          }
          var seq = cur?.seq;
          if (seq == null) {
            final maxSeq = db.matchEvents.seq.max();
            final q = db.selectOnly(db.matchEvents)
              ..addColumns([maxSeq])
              ..where(db.matchEvents.matchId.equals(e.matchId));
            seq = (await q.map((r) => r.read(maxSeq)).getSingle() ?? 0) + 1;
          }
          await db.into(db.matchEvents).insertOnConflictUpdate(
              _eventToCompanion(
                  e.copyWith(seq: seq, syncStatus: SyncStatus.synced)));
          touched.add(e.matchId);
          changed++;
        }
        for (final id in touched) {
          await _refreshCache(id);
        }
        return changed;
      });

  // ================================================================ mapping

  static String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static DateTime _dt(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

  static DateTime? _dtn(int? ms) => ms == null ? null : _dt(ms);

  static MatchFormat _decodeFormat(String json) =>
      MatchFormat.fromJson(jsonDecode(json) as Map<String, dynamic>);

  static MatchInfo _matchFromRow(MatchRow r) => MatchInfo(
        id: r.id,
        sport: r.sport,
        format: _decodeFormat(r.formatJson),
        status: MatchStatus.fromCode(r.status),
        homeName: r.homeName,
        awayName: r.awayName,
        homeTeamId: r.homeTeamId,
        awayTeamId: r.awayTeamId,
        category: r.category,
        competition: r.competition,
        venue: r.venue,
        season: r.season,
        notes: r.notes,
        scheduledAt: _dtn(r.scheduledAt),
        homeScore: r.homeScore,
        awayScore: r.awayScore,
        startedAt: _dtn(r.startedAt),
        endedAt: _dtn(r.endedAt),
        createdAt: _dt(r.createdAt),
        updatedAt: _dt(r.updatedAt),
        deviceId: r.deviceId,
        ownerUserId: r.ownerUserId,
        revision: r.revision,
        syncStatus: SyncStatus.fromCode(r.syncStatus),
        deletedAt: _dtn(r.deletedAt),
      );

  static MatchEvent _eventFromRow(MatchEventRow r) => MatchEvent(
        id: r.id,
        matchId: r.matchId,
        type: r.type,
        subtype: r.subtype,
        team: TeamSide.fromCode(r.team),
        period: r.period,
        matchTime: Duration(milliseconds: r.matchTimeMs),
        periodTime: Duration(milliseconds: r.periodTimeMs),
        timestamp: _dt(r.occurredAt),
        createdAt: _dt(r.createdAt),
        updatedAt: _dt(r.updatedAt),
        deviceId: r.deviceId,
        actionId: r.actionId,
        seq: r.seq,
        revision: r.revision,
        voidedAt: _dtn(r.voidedAt),
        syncStatus: SyncStatus.fromCode(r.syncStatus),
        metadata: _decodeMeta(r.metadataJson),
      );

  static Map<String, dynamic> _decodeMeta(String json) {
    try {
      final v = jsonDecode(json);
      return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static MatchEventsCompanion _eventToCompanion(MatchEvent e) =>
      MatchEventsCompanion(
        id: Value(e.id),
        matchId: Value(e.matchId),
        type: Value(e.type),
        subtype: Value(e.subtype),
        team: Value(e.team?.code),
        period: Value(e.period),
        matchTimeMs: Value(e.matchTime.inMilliseconds),
        periodTimeMs: Value(e.periodTime.inMilliseconds),
        occurredAt: Value(e.timestamp.millisecondsSinceEpoch),
        createdAt: Value(e.createdAt.millisecondsSinceEpoch),
        updatedAt: Value(e.updatedAt.millisecondsSinceEpoch),
        deviceId: Value(e.deviceId),
        actionId: Value(e.actionId),
        seq: Value(e.seq),
        revision: Value(e.revision),
        voidedAt: Value(e.voidedAt?.millisecondsSinceEpoch),
        syncStatus: Value(e.syncStatus.code),
        metadataJson: Value(jsonEncode(e.metadata)),
      );
}
