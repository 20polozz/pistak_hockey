import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/core/clock.dart';
import 'package:pistak/core/time_format.dart';
import 'package:pistak/data/db/app_database.dart';
import 'package:pistak/data/repositories/drift_match_repository.dart';
import 'package:pistak/domain/match/match_event.dart';
import 'package:pistak/domain/sport/match_format.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';
import 'package:pistak/ui/match_controller.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('direct free hit at 10 fouls, then every 5 (15, 20…)', () {
    final f = rollerHockey.defaultFormat;
    expect(f.foulLimit, 10);
    final sanctions = [
      for (var n = 1; n <= 26; n++)
        if (f.isFoulSanction(n)) n
    ];
    expect(sanctions, [10, 15, 20, 25]);
    expect(f.nextFoulSanction(3), 10);
    expect(f.nextFoulSanction(10), 10);
    expect(f.nextFoulSanction(11), 15);
    expect(f.nextFoulSanction(16), 20);
    final once = f.copyWith(foulLimitEvery: 0);
    expect(once.isFoulSanction(15), isFalse);
    expect(once.nextFoulSanction(11), isNull);
    // Old saved formats (no field) get the 5-by-5 rule.
    final json = f.toJson()..remove('foulLimitEvery');
    expect(MatchFormat.fromJson(json).foulLimitEvery, 5);
  });

  test('hockey: 2 timeouts per team and half, 1:00 and 0:30', () async {
    expect(rollerHockey.defaultFormat.timeoutSlots,
        const [Duration(minutes: 1), Duration(seconds: 30)]);
    expect(formatTimeoutLength(const Duration(minutes: 1)), "1'");
    expect(formatTimeoutLength(const Duration(seconds: 30)), "30''");

    final db = AppDatabase(NativeDatabase.memory());
    final clock = FakeClock(DateTime.utc(2026, 10, 12, 18));
    final repo = DriftMatchRepository(db, deviceId: 'd', clock: clock);
    final m = await repo.createMatch(
        sport: rollerHockey.id, format: rollerHockey.defaultFormat);
    final c = MatchController(
        matchId: m.id, deviceId: 'd', repository: repo, clock: clock);
    await c.startMatch();
    clock.advance(const Duration(minutes: 5));

    await c.timeout(TeamSide.home, duration: const Duration(seconds: 30));
    var s = await c.currentState();
    expect(s.activeTimeout!.duration, const Duration(seconds: 30));
    expect(s.timeoutsLeft(TeamSide.home), const [Duration(minutes: 1)]);
    expect(s.timeoutsLeft(TeamSide.away).length, 2);
    clock.advance(const Duration(seconds: 10));
    expect(s.timeoutRemainingAt(clock.now()), const Duration(seconds: 20));
    await c.endTimeout();
    await c.resume();

    // No duration given: takes the one left (1:00).
    await c.timeout(TeamSide.home);
    s = await c.currentState();
    expect(s.activeTimeout!.duration, const Duration(minutes: 1));
    expect(s.timeoutsLeft(TeamSide.home), isEmpty);
    expect(s.home.timeouts, 2);
    await db.close();
  });

  test('foul counter targets 10 then 15', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final clock = FakeClock(DateTime.utc(2026, 10, 12, 18));
    final repo = DriftMatchRepository(db, deviceId: 'd', clock: clock);
    final m = await repo.createMatch(
        sport: rollerHockey.id,
        format: rollerHockey.defaultFormat.copyWith(stopClockOnEvents: false));
    final c = MatchController(
        matchId: m.id, deviceId: 'd', repository: repo, clock: clock);
    await c.startMatch();
    for (var i = 0; i < 9; i++) {
      await c.foul(TeamSide.away);
    }
    var s = await c.currentState();
    expect(s.foulLimitNear(TeamSide.away), isTrue);
    expect(s.foulTarget(TeamSide.away), 10);
    await c.foul(TeamSide.away);
    s = await c.currentState();
    expect(s.foulLimitReached(TeamSide.away), isTrue);
    await c.foul(TeamSide.away);
    s = await c.currentState();
    expect(s.foulLimitReached(TeamSide.away), isFalse);
    expect(s.foulTarget(TeamSide.away), 15);
    for (var i = 0; i < 3; i++) {
      await c.foul(TeamSide.away);
    }
    s = await c.currentState();
    expect(s.foulLimitNear(TeamSide.away), isTrue, reason: '14th → 15th');
    await db.close();
  });

  test('goalkeeper saves are counted and do not stop the clock', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final clock = FakeClock(DateTime.utc(2026, 10, 12, 18));
    final repo = DriftMatchRepository(db, deviceId: 'd', clock: clock);
    final m = await repo.createMatch(
        sport: rollerHockey.id, format: rollerHockey.defaultFormat);
    final c = MatchController(
        matchId: m.id, deviceId: 'd', repository: repo, clock: clock);
    await c.startMatch();
    final ev = await c.save(TeamSide.home);
    expect(ev.single.type, EventTypes.save);
    await c.save(TeamSide.home);
    await c.save(TeamSide.away);
    final s = await c.currentState();
    expect(s.home.saves, 2);
    expect(s.away.saves, 1);
    expect(s.isClockRunning, isTrue);
    await c.undo();
    expect((await c.currentState()).away.saves, 0);
    await db.close();
  });

  test('hockey: team fouls add up over the whole match (no reset at half)',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final clock = FakeClock(DateTime.utc(2026, 10, 12, 18));
    final repo = DriftMatchRepository(db, deviceId: 'd', clock: clock);
    final m = await repo.createMatch(
        sport: rollerHockey.id,
        format: rollerHockey.defaultFormat.copyWith(stopClockOnEvents: false));
    final c = MatchController(
        matchId: m.id, deviceId: 'd', repository: repo, clock: clock);
    await c.startMatch();
    for (var i = 0; i < 6; i++) {
      await c.foul(TeamSide.home);
    }
    await c.endPeriod();
    await c.startNextPeriod();
    var s = await c.currentState();
    expect(s.period, 2);
    expect(s.foulCount(TeamSide.home), 6, reason: 'not reset at half time');
    for (var i = 0; i < 4; i++) {
      await c.foul(TeamSide.home);
    }
    s = await c.currentState();
    expect(s.foulCount(TeamSide.home), 10);
    expect(s.foulLimitReached(TeamSide.home), isTrue);
    expect(s.foulTarget(TeamSide.away), 10);
    // A format that resets each period only counts this half.
    expect(
        MatchFormat.fromJson(rollerHockey.defaultFormat
                .copyWith(foulsResetEachPeriod: true)
                .toJson())
            .foulsResetEachPeriod,
        isTrue);
    await db.close();
  });

  test('big clock counts down 25:00 → 0:00 per period', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final clock = FakeClock(DateTime.utc(2026, 10, 12, 18));
    final repo = DriftMatchRepository(db, deviceId: 'd', clock: clock);
    final m = await repo.createMatch(
        sport: rollerHockey.id,
        format: rollerHockey.defaultFormat.copyWith(stopClockOnEvents: false));
    final c = MatchController(
        matchId: m.id, deviceId: 'd', repository: repo, clock: clock);
    var s = await c.currentState();
    expect(s.remainingAt(clock.now()), const Duration(minutes: 25));
    await c.startMatch();
    clock.advance(const Duration(minutes: 3, seconds: 20));
    s = await c.currentState();
    expect(
        s.remainingAt(clock.now()), const Duration(minutes: 21, seconds: 40));
    expect(s.matchTimeAt(clock.now()), const Duration(minutes: 3, seconds: 20),
        reason: 'events keep the elapsed time');
    clock.advance(const Duration(minutes: 30));
    expect(s.remainingAt(clock.now()), Duration.zero, reason: 'never < 0');
    await c.endPeriod();
    await c.startNextPeriod();
    s = await c.currentState();
    expect(s.remainingAt(clock.now()), const Duration(minutes: 25));
    await db.close();
  });
}
