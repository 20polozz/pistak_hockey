// Requires a native SQLite library on the host running `flutter test`
// (Linux: libsqlite3, macOS: built in, Windows: sqlite3.dll on PATH).
// See docs/SETUP.md.
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/auth/auth_service.dart';
import 'package:pistak/core/clock.dart';
import 'package:pistak/data/db/app_database.dart';
import 'package:pistak/data/repositories/drift_match_repository.dart';
import 'package:pistak/data/repositories/settings_repository.dart';
import 'package:pistak/domain/match/match_event.dart';
import 'package:pistak/domain/match/match_info.dart';
import 'package:pistak/domain/match/match_state.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';
import 'package:pistak/sync/remote_sync_api.dart';
import 'package:pistak/sync/sync_engine.dart';
import 'package:pistak/ui/match_controller.dart';

/// Fake backend with the same idempotency rule as the real one:
/// upsert by id, only if the incoming revision is higher.
class FakeServer implements RemoteSyncApi {
  bool online = true;

  /// Simulates a connection drop AFTER the server stored a batch but BEFORE
  /// the client received the acknowledgement (worst case for duplicates).
  bool dropNextAck = false;

  final events = <String, MatchEvent>{};
  final matches = <String, MatchInfo>{};
  int eventPayloadsReceived = 0;

  @override
  Future<PushResult> pushEvents(List<MatchEvent> batch) async {
    if (!online) throw const SyncUnavailable('offline');
    final accepted = <String, int>{};
    for (final e in batch) {
      eventPayloadsReceived++;
      final existing = events[e.id];
      if (existing == null || existing.revision < e.revision) {
        events[e.id] = e;
      }
      accepted[e.id] = e.revision;
    }
    if (dropNextAck) {
      dropNextAck = false;
      throw const SyncUnavailable('connection lost before ack');
    }
    return PushResult(accepted);
  }

  @override
  Future<PushResult> pushMatches(List<MatchInfo> batch) async {
    if (!online) throw const SyncUnavailable('offline');
    final accepted = <String, int>{};
    for (final m in batch) {
      final existing = matches[m.id];
      if (existing == null || existing.revision < m.revision) matches[m.id] = m;
      accepted[m.id] = m.revision;
    }
    return PushResult(accepted);
  }
}

class SignedInAuth implements AuthService {
  @override
  String? get currentUserId => 'user-1';
  @override
  bool get isSignedIn => true;
  @override
  Future<String?> accessToken() async => 'token';
}

/// One "app process": database + repository + controller on a given file.
class AppProcess {
  AppProcess(File file, this.clock, this.server)
      : db = AppDatabase(NativeDatabase(file)) {
    settings = SettingsRepository(db);
  }

  final AppDatabase db;
  final FakeClock clock;
  final FakeServer server;
  late final SettingsRepository settings;
  late DriftMatchRepository repo;
  late SyncEngine sync;

  Future<void> boot() async {
    final deviceId = await settings.ensureDeviceId();
    repo = DriftMatchRepository(db, deviceId: deviceId, clock: clock);
    sync = SyncEngine(repository: repo, api: server, auth: SignedInAuth());
  }

  MatchController controller(String matchId) => MatchController(
        matchId: matchId,
        deviceId: repo.deviceId,
        repository: repo,
        clock: clock,
      );

  Future<void> close() async {
    sync.dispose();
    await db.close();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pistak_test_');
    file = File('${dir.path}/pistak.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('CRITICAL: 50 offline events survive restart and sync exactly once',
      () async {
    final clock = FakeClock(DateTime.utc(2026, 10, 12, 16, 30));
    final server = FakeServer();

    // 1. Internet ON — 2. create match.
    var app = AppProcess(file, clock, server);
    await app.boot();
    final deviceId = app.repo.deviceId;
    final match = await app.repo.createMatch(
        sport: rollerHockey.id, format: rollerHockey.defaultFormat);
    expect((await app.sync.syncOnce()).ok, isTrue);
    expect(server.matches.containsKey(match.id), isTrue);

    // 3. Internet OFF.
    server.online = false;

    // 4. Record ≥50 events: start (2) + 47 recordings + pause + foul = 51.
    final c = app.controller(match.id);
    await c.startMatch(); // 2 events
    final kinds = <Future<List<MatchEvent>> Function()>[
      () => c.goal(TeamSide.home),
      () => c.foul(TeamSide.away),
      () => c.card(CardColors.blue),
      () => c.goal(TeamSide.away),
      () => c.foul(TeamSide.home),
      () => c.incident(IncidentKinds.text, text: 'Problema amb la pista'),
    ];
    for (var i = 0; i < 47; i++) {
      clock.advance(const Duration(seconds: 20));
      await kinds[i % kinds.length]();
    }
    clock.advance(const Duration(seconds: 20));
    await c.pause(); // 1 event
    clock.advance(const Duration(seconds: 5));
    await c.foul(TeamSide.home); // 1 event → 2 + 47 + 1 + 1 = 51
    var all = await app.repo.getEvents(match.id);
    expect(all.length, 51);

    // Sync attempt while offline fails silently; nothing is lost.
    final offlineReport = await app.sync.syncOnce();
    expect(offlineReport.ok, isFalse);
    expect((await app.repo.pendingEvents(limit: 1000)).length, 51);

    // 5. Close the app (process dies).
    await app.close();

    // 6. Open the app again on the same storage.
    clock.advance(const Duration(minutes: 3));
    app = AppProcess(file, clock, server);
    await app.boot();

    // 7. Check data: same device, all events, consistent state, recoverable.
    expect(app.repo.deviceId, deviceId);
    all = await app.repo.getEvents(match.id);
    expect(all.length, 51);
    expect(all.map((e) => e.id).toSet().length, 51);
    final active = await app.repo.watchActiveMatch().first;
    expect(active?.id, match.id, reason: '"Partit en curs" must be offered');
    final state = await app.controller(match.id).currentState();
    expect(state.phase, MatchPhase.paused);
    expect(state.home.goals, 8); // i % 6 == 0 for i in 0..46 → 8
    expect(state.away.goals, 8); // i % 6 == 3 → 8
    expect(active!.homeScore, 8);
    expect(active.awayScore, 8);

    // 8. Internet ON — 9. sync, with a connection drop before the ack.
    server.online = true;
    server.dropNextAck = true;
    expect((await app.sync.syncOnce()).ok, isFalse);
    expect(server.events.length, 51, reason: 'stored but not acked');
    final report = await app.sync.syncOnce();
    expect(report.ok, isTrue);

    // 10. Server content — 11. no duplicates — 12. nothing missing.
    expect(server.eventPayloadsReceived, 102); // every event was sent twice…
    expect(server.events.length, 51); // …but stored once.
    expect(server.events.keys.toSet(), all.map((e) => e.id).toSet());
    expect(await app.repo.pendingEvents(limit: 1000), isEmpty);

    // A third sync sends nothing.
    final again = await app.sync.syncOnce();
    expect(again.events, 0);
    expect(server.eventPayloadsReceived, 102);

    await app.close();
  });

  test('append is atomic and refreshes the match cache', () async {
    final clock = FakeClock(DateTime.utc(2026, 10, 12, 18, 30));
    final app = AppProcess(file, clock, FakeServer());
    await app.boot();
    final m = await app.repo
        .createMatch(sport: rollerHockey.id, format: rollerHockey.defaultFormat);
    expect(m.status, MatchStatus.notStarted);
    expect(m.isUntitled, isTrue);

    final c = app.controller(m.id);
    await c.startMatch();
    clock.advance(const Duration(minutes: 3, seconds: 42));
    final goal = (await c.goal(TeamSide.home)).single;
    expect(goal.seq, 3);

    final info = (await app.repo.getMatch(m.id))!;
    expect(info.status, MatchStatus.live);
    expect(info.homeScore, 1);
    expect(info.startedAt, DateTime.utc(2026, 10, 12, 18, 30));
    final stored = (await app.repo.getEvents(m.id)).last;
    expect(stored.matchTime, const Duration(minutes: 3, seconds: 42));
    await app.close();
  });

  test('undo voids the whole last action and keeps history', () async {
    final clock = FakeClock(DateTime.utc(2026, 10, 12, 18, 30));
    final app = AppProcess(file, clock, FakeServer());
    await app.boot();
    final m = await app.repo
        .createMatch(sport: rollerHockey.id, format: rollerHockey.defaultFormat);
    final c = app.controller(m.id);
    await c.startMatch();
    clock.advance(const Duration(minutes: 1));
    await c.timeout(TeamSide.away); // TIMEOUT + CLOCK_PAUSE
    final undone = await c.undo();
    expect(undone.map((e) => e.type).toSet(),
        {EventTypes.timeout, EventTypes.clockPause});
    final events = await app.repo.getEvents(m.id);
    expect(events.length, 4);
    expect(events.where((e) => e.isVoided).length, 2);
    expect((await c.currentState()).isClockRunning, isTrue);

    // Restore one of them from the timeline.
    await c.setVoided(undone.first, false);
    expect((await app.repo.getEvents(m.id)).where((e) => e.isVoided).length, 1);
    await app.close();
  });

  test('an event edited during sync stays pending (no lost edit)', () async {
    final clock = FakeClock(DateTime.utc(2026, 10, 12, 18, 30));
    final server = FakeServer();
    final app = AppProcess(file, clock, server);
    await app.boot();
    final m = await app.repo
        .createMatch(sport: rollerHockey.id, format: rollerHockey.defaultFormat);
    final c = app.controller(m.id);
    final card = (await c.card(CardColors.red)).single;

    final pending = await app.repo.pendingEvents();
    await server.pushEvents(pending); // server has revision 1
    await c.setTeam(card, TeamSide.home); // local revision 2 meanwhile
    await app.repo.markEventsSynced({card.id: 1}); // late ack of revision 1

    final after = (await app.repo.pendingEvents()).single;
    expect(after.id, card.id);
    expect(after.revision, 2);
    expect(after.team, TeamSide.home);

    await app.sync.syncOnce();
    expect(server.events[card.id]!.team, TeamSide.home);
    expect(await app.repo.pendingEvents(), isEmpty);
    await app.close();
  });

  test('re-delivering the same event id locally is a no-op', () async {
    final clock = FakeClock(DateTime.utc(2026, 10, 12, 18, 30));
    final app = AppProcess(file, clock, FakeServer());
    await app.boot();
    final m = await app.repo
        .createMatch(sport: rollerHockey.id, format: rollerHockey.defaultFormat);
    final goal = (await app.controller(m.id).goal(TeamSide.away)).single;
    await app.repo.appendEvents(m.id, [goal.copyWith(seq: 0)]);
    final events = await app.repo.getEvents(m.id);
    expect(events.length, 1);
    expect((await app.repo.getMatch(m.id))!.awayScore, 1);
    await app.close();
  });

  test('guest users never send anything (local only)', () async {
    final server = FakeServer();
    final db = AppDatabase(NativeDatabase.memory());
    final repo = DriftMatchRepository(db,
        deviceId: 'd', clock: FakeClock(DateTime.utc(2026)));
    await repo.createMatch(
        sport: rollerHockey.id, format: rollerHockey.defaultFormat);
    final engine = SyncEngine(
        repository: repo, api: server, auth: const GuestAuthService());
    final report = await engine.syncOnce();
    expect(report.ok, isTrue);
    expect(engine.state, SyncState.localOnly);
    expect(server.matches, isEmpty);
    engine.dispose();
    await db.close();
  });
}
