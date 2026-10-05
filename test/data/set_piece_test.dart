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

  test('in-game penalties and free hits: score, stats, time, undo', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final clock = FakeClock(DateTime.utc(2026, 10, 12, 18));
    final repo = DriftMatchRepository(db, deviceId: 'd', clock: clock);
    final m = await repo.createMatch(
        sport: rollerHockey.id, format: rollerHockey.defaultFormat);
    final c = MatchController(
        matchId: m.id, deviceId: 'd', repository: repo, clock: clock);
    await c.startMatch();
    clock.advance(const Duration(minutes: 5));
    final pressedAt = clock.now();
    clock.advance(const Duration(seconds: 20)); // choosing the result
    final goal = (await c.setPiece(TeamSide.home,
            kind: ShotKinds.penalty, scored: true, at: pressedAt))
        .single;
    expect(goal.type, EventTypes.goal);
    expect(goal.matchTime, const Duration(minutes: 5),
        reason: 'time of the button press');
    await c.setPiece(TeamSide.home, kind: ShotKinds.penalty, scored: false);
    await c.setPiece(TeamSide.away, kind: ShotKinds.freeHit, scored: false);

    var s = await c.currentState();
    expect(s.home.goals, 1);
    expect(s.away.goals, 0);
    expect((s.home.penaltyScored, s.home.penaltyAttempts), (1, 2));
    expect((s.away.freeHitScored, s.away.freeHitAttempts), (0, 1));
    expect((await repo.getMatch(m.id))!.homeScore, 1);

    await c.undo(); // the missed free hit
    s = await c.currentState();
    expect(s.away.freeHitAttempts, 0);
    await db.close();
  });
}
