import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/core/clock.dart';
import 'package:pistak/data/db/app_database.dart';
import 'package:pistak/data/repositories/drift_match_repository.dart';
import 'package:pistak/domain/match/match_event.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';
import 'package:pistak/ui/match_controller.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('goal, foul, card, penalty and free hit stop the clock (one action)',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final clock = FakeClock(DateTime.utc(2026, 10, 12, 18));
    final repo = DriftMatchRepository(db, deviceId: 'd', clock: clock);
    final m = await repo.createMatch(
        sport: rollerHockey.id, format: rollerHockey.defaultFormat);
    expect(rollerHockey.defaultFormat.stopClockOnEvents, isTrue);
    final c = MatchController(
        matchId: m.id, deviceId: 'd', repository: repo, clock: clock);
    await c.startMatch();
    clock.advance(const Duration(minutes: 3));

    final goal = await c.goal(TeamSide.home);
    expect(goal.map((e) => e.type), [EventTypes.goal, EventTypes.clockPause]);
    expect(goal.last.subtype, PauseReasons.event);
    expect(goal.first.actionId, goal.last.actionId);
    var s = await c.currentState();
    expect(s.isClockRunning, isFalse);
    expect(s.lastEvent!.type, EventTypes.goal, reason: 'undo bar shows GOAL');

    // Time is frozen while stopped.
    clock.advance(const Duration(seconds: 45));
    expect(s.matchTimeAt(clock.now()), const Duration(minutes: 3));

    // Another event while already stopped doesn't add a second pause.
    expect((await c.foul(TeamSide.away)).length, 1);

    // Undo the foul, then the goal: the clock runs again, as before the goal.
    await c.undo();
    await c.undo();
    s = await c.currentState();
    expect(s.isClockRunning, isTrue);
    expect(s.home.goals, 0);

    for (final action in <Future<List<MatchEvent>> Function()>[
      () => c.foul(TeamSide.home),
      () => c.card(CardColors.blue, team: TeamSide.away),
      () => c.setPiece(TeamSide.home, kind: ShotKinds.penalty, scored: false),
      () => c.setPiece(TeamSide.away, kind: ShotKinds.freeHit, scored: true),
    ]) {
      if (!(await c.currentState()).isClockRunning) await c.resume();
      clock.advance(const Duration(seconds: 30));
      final ev = await action();
      expect(ev.last.type, EventTypes.clockPause);
      expect((await c.currentState()).isClockRunning, isFalse);
    }
    // Timeouts keep their own rule.
    await c.resume();
    final to = await c.timeout(TeamSide.home);
    expect(to.map((e) => e.subtype).last, PauseReasons.timeout);
    await db.close();
  });

  test('a category can play continuous time', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = DriftMatchRepository(db,
        deviceId: 'd', clock: FakeClock(DateTime.utc(2026)));
    final m = await repo.createMatch(
        sport: rollerHockey.id,
        format: rollerHockey.defaultFormat.copyWith(stopClockOnEvents: false));
    final c = MatchController(
        matchId: m.id,
        deviceId: 'd',
        repository: repo,
        clock: FakeClock(DateTime.utc(2026)));
    await c.startMatch();
    expect((await c.goal(TeamSide.home)).length, 1);
    expect((await c.currentState()).isClockRunning, isTrue);
    await db.close();
  });
}
