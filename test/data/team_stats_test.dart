import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/core/clock.dart';
import 'package:pistak/data/db/app_database.dart';
import 'package:pistak/data/repositories/drift_match_repository.dart';
import 'package:pistak/domain/match/event_factory.dart';
import 'package:pistak/domain/match/match_event.dart';
import 'package:pistak/domain/match/match_projector.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';
import 'package:pistak/domain/stats/team_stats.dart';
import 'package:pistak/ui/match_controller.dart';

/// Continuous clock: these tests are about other things than the automatic
/// stops of effective time (see test/domain/effective_time_test.dart).
final continuousTime =
    rollerHockey.defaultFormat.copyWith(stopClockOnEvents: false);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('season record and player ranking of one team', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final clock = FakeClock(DateTime.utc(2026, 10, 12, 18));
    final repo = DriftMatchRepository(db, deviceId: 'd', clock: clock);

    Future<MatchController> match(
        {required bool weAreHome, String season = '2026-27'}) async {
      final m = await repo.createMatch(
          sport: rollerHockey.id,
          format: continuousTime,
          homeTeamId: weAreHome ? 'vic' : null,
          awayTeamId: weAreHome ? null : 'vic',
          season: season);
      final c = MatchController(
          matchId: m.id, deviceId: 'd', repository: repo, clock: clock);
      await c.startMatch();
      return c;
    }

    Future<void> goal(MatchController c, TeamSide side,
        {String? player, String? assist}) async {
      clock.advance(const Duration(minutes: 1));
      final g = (await c.goal(side)).single;
      await c.setMeta(g, {
        if (player != null) MetaKeys.playerId: player,
        if (player != null) MetaKeys.playerName: player.toUpperCase(),
        if (assist != null) MetaKeys.assistId: assist,
        if (assist != null) MetaKeys.assistName: assist.toUpperCase(),
      });
    }

    // Match 1 (home): 3-1 win. Marc 2 goals, Pau 1 goal + 1 assist.
    final m1 = await match(weAreHome: true);
    await goal(m1, TeamSide.home, player: 'marc', assist: 'pau');
    await goal(m1, TeamSide.home, player: 'marc');
    await goal(m1, TeamSide.away);
    await goal(m1, TeamSide.home, player: 'pau');
    final card = (await m1.card(CardColors.blue, team: TeamSide.home)).single;
    await m1
        .setMeta(card, {MetaKeys.playerId: 'pau', MetaKeys.playerName: 'PAU'});
    await m1.endMatch();

    // Match 2 (away): 1-1, lost on the shoot-out.
    final m2 = await match(weAreHome: false);
    await goal(m2, TeamSide.away, player: 'pau');
    await goal(m2, TeamSide.home);
    await m2.endPeriod(); // 1st half
    await m2.startNextPeriod();
    await m2.endPeriod(then: PeriodEndChoice.shootout);
    await m2.shootoutAttempt(TeamSide.home, scored: true);
    await m2.shootoutAttempt(TeamSide.away, scored: false);
    await m2.endMatch();

    // Another season: must not count.
    final m3 = await match(weAreHome: true, season: '2025-26');
    await goal(m3, TeamSide.home, player: 'marc');
    await m3.endMatch();

    final played = <PlayedMatch>[];
    for (final info in await repo.watchMatches().first) {
      final ev = await repo.getEvents(info.id);
      played.add(PlayedMatch(
          info, const MatchProjector().project(info.format, ev), ev));
    }
    final t = TeamStats.compute(played, 'vic', season: '2026-27');
    expect((t.played, t.wins, t.draws, t.losses), (2, 1, 0, 1));
    expect((t.goalsFor, t.goalsAgainst), (4, 2));
    expect(t.points, 3);
    expect(t.blue, 1);
    final r = t.ranking;
    expect(r.map((p) => (p.label, p.goals, p.assists)).toList(),
        [('PAU', 2, 1), ('MARC', 2, 0)]);
    expect(r.first.blue, 1);

    final all = TeamStats.compute(played, 'vic');
    expect(all.played, 3);
    expect(all.players['marc']!.goals, 3);
    await db.close();
  });
}
