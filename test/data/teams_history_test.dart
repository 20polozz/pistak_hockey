import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/core/clock.dart';
import 'package:pistak/data/db/app_database.dart';
import 'package:pistak/data/repositories/drift_match_repository.dart';
import 'package:pistak/data/repositories/drift_team_repository.dart';
import 'package:pistak/domain/match/match_event.dart';
import 'package:pistak/domain/match/match_filter.dart';
import 'package:pistak/domain/match/match_info.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';
import 'package:pistak/domain/team/team.dart';
import 'package:pistak/ui/match_controller.dart';

/// Continuous clock: these tests are about other things than the automatic
/// stops of effective time (see test/domain/effective_time_test.dart).
final continuousTime =
    rollerHockey.defaultFormat.copyWith(stopClockOnEvents: false);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late FakeClock clock;
  late DriftTeamRepository teams;
  late DriftMatchRepository matches;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clock = FakeClock(DateTime.utc(2026, 10, 12, 16));
    teams = DriftTeamRepository(db, clock: clock);
    matches = DriftMatchRepository(db, deviceId: 'd', clock: clock);
  });
  tearDown(() => db.close());

  test('teams and roster CRUD (optional data)', () async {
    final t = await teams.createTeam(name: ' CP Exemple ', category: 'Sènior');
    expect(t.name, 'CP Exemple');
    await teams.addMember(t.id,
        role: MemberRole.player, name: 'Joan', number: 8);
    await teams.addMember(t.id,
        role: MemberRole.goalkeeper, name: 'Pau', number: 1);
    final coach =
        await teams.addMember(t.id, role: MemberRole.coach, name: 'Marta');
    expect((await teams.getMembers(t.id)).length, 3);
    await teams.deleteMember(coach.id);
    final left = await teams.getMembers(t.id);
    expect(left.map((m) => m.label), containsAll(['#8 Joan', '#1 Pau']));
    await teams.saveTeam(t.copyWith(name: 'CP Exemple B'));
    final saved = (await teams.getTeam(t.id))!;
    expect(saved.name, 'CP Exemple B');
    expect(saved.revision, 2);
    expect(saved.syncStatus, SyncStatus.pending);
    await teams.deleteTeam(t.id);
    expect(await teams.getTeams(), isEmpty);
  });

  test('a match can be linked to teams; events can get a player later',
      () async {
    final home = await teams.createTeam(name: 'CP Exemple');
    final p = await teams.addMember(home.id,
        role: MemberRole.player, name: 'Joan', number: 8);
    final m = await matches.createMatch(
        sport: rollerHockey.id,
        format: continuousTime,
        homeName: home.name,
        homeTeamId: home.id,
        awayName: 'HC Rival');
    expect((await matches.getMatch(m.id))!.homeTeamId, home.id);
    final c = MatchController(
        matchId: m.id, deviceId: 'd', repository: matches, clock: clock);
    await c.startMatch();
    final goal = (await c.goal(TeamSide.home)).single;
    expect(goal.playerName, isNull, reason: 'player is never required');
    await c.updateEvent(goal.copyWith(metadata: {
      MetaKeys.playerId: p.id,
      MetaKeys.playerName: p.label,
    }));
    final stored =
        (await matches.getEvents(m.id)).firstWhere((e) => e.id == goal.id);
    expect(stored.playerName, '#8 Joan');
  });

  group('history filters', () {
    late Team mine;
    late List<MatchInfo> all;

    setUp(() async {
      mine = await teams.createTeam(name: 'CP Exemple');
      Future<void> played(String home, String away, int hs, int as,
          {String? comp, String? cat, required DateTime at}) async {
        clock.set(at);
        final m = await matches.createMatch(
            sport: rollerHockey.id,
            format: continuousTime,
            homeName: home,
            awayName: away,
            homeTeamId: home == mine.name ? mine.id : null,
            competition: comp,
            category: cat);
        final c = MatchController(
            matchId: m.id, deviceId: 'd', repository: matches, clock: clock);
        await c.startMatch();
        for (var i = 0; i < hs; i++) {
          await c.goal(TeamSide.home);
        }
        for (var i = 0; i < as; i++) {
          await c.goal(TeamSide.away);
        }
        await c.endMatch();
      }

      await played('CP Exemple', 'HC A', 4, 2,
          comp: 'Lliga', cat: 'Sènior', at: DateTime.utc(2026, 10, 12, 16));
      await played('HC B', 'CP Exemple', 1, 1,
          comp: 'Lliga', cat: 'Sènior', at: DateTime.utc(2026, 10, 5, 16));
      await played('HC C', 'CP Exemple', 3, 0,
          comp: 'Copa', cat: 'Júnior', at: DateTime.utc(2026, 9, 20, 16));
      await played('HC X', 'HC Y', 0, 0, at: DateTime.utc(2026, 9, 1, 16));
      all = await matches.watchMatches().first;
    });

    test('by team (linked or by name) and result', () {
      final f = MatchFilter(team: mine);
      expect(f.apply(all).length, 3);
      expect(f.copyWith(result: ResultFilter.win).apply(all).single.awayName,
          'HC A');
      expect(f.copyWith(result: ResultFilter.draw).apply(all).single.homeName,
          'HC B');
      expect(f.copyWith(result: ResultFilter.loss).apply(all).single.homeName,
          'HC C');
    });

    test('by competition, category and dates', () {
      expect(const MatchFilter(competition: 'Lliga').apply(all).length, 2);
      expect(const MatchFilter(category: 'Júnior').apply(all).length, 1);
      final oct =
          MatchFilter(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31));
      expect(oct.apply(all).length, 2);
      expect(const MatchFilter().apply(all).length, 4);
    });
  });

  test('next scheduled match', () async {
    clock.set(DateTime.utc(2026, 10, 10, 9));
    await matches.createMatch(
        sport: rollerHockey.id,
        format: continuousTime,
        homeName: 'Later',
        scheduledAt: DateTime.utc(2026, 10, 20, 16));
    await matches.createMatch(
        sport: rollerHockey.id,
        format: continuousTime,
        homeName: 'Soon',
        scheduledAt: DateTime.utc(2026, 10, 12, 16));
    await matches.createMatch(
        sport: rollerHockey.id,
        format: continuousTime,
        homeName: 'Past',
        scheduledAt: DateTime.utc(2026, 10, 1, 16));
    final all = await matches.watchMatches().first;
    expect(nextScheduledMatch(all, DateTime(2026, 10, 10))?.homeName, 'Soon');
  });

  test('migration v2 → v3 keeps existing matches', () async {
    final dir = Directory.systemTemp.createTempSync('pistak_mig_');
    final file = File('${dir.path}/db.sqlite');
    var d = AppDatabase(NativeDatabase(file));
    final repo = DriftMatchRepository(d, deviceId: 'd', clock: clock);
    final m = await repo.createMatch(
        sport: rollerHockey.id, format: continuousTime, homeName: 'Abans');
    // Turn the file back into a v2 database.
    await d.customStatement('DROP TABLE teams');
    await d.customStatement('DROP TABLE team_members');
    await d.customStatement('ALTER TABLE matches DROP COLUMN home_team_id');
    await d.customStatement('ALTER TABLE matches DROP COLUMN away_team_id');
    await d.customStatement('PRAGMA user_version = 2');
    await d.close();

    d = AppDatabase(NativeDatabase(file));
    final again = DriftMatchRepository(d, deviceId: 'd', clock: clock);
    final kept = (await again.getMatch(m.id))!;
    expect(kept.homeName, 'Abans');
    expect(kept.homeTeamId, isNull);
    final t =
        await DriftTeamRepository(d, clock: clock).createTeam(name: 'Nou');
    expect(t.name, 'Nou');
    await d.close();
    dir.deleteSync(recursive: true);
  });
}
