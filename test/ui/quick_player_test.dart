import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/app/theme.dart';
import 'package:pistak/core/clock.dart';
import 'package:pistak/data/db/app_database.dart';
import 'package:pistak/data/repositories/drift_match_repository.dart';
import 'package:pistak/data/repositories/drift_team_repository.dart';
import 'package:pistak/domain/match/match_event.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';
import 'package:pistak/domain/team/team.dart';
import 'package:pistak/l10n/app_localizations.dart';
import 'package:pistak/ui/match_controller.dart';
import 'package:pistak/ui/providers.dart';
import 'package:pistak/ui/screens/match_screen.dart';

import 'real_fonts.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  setUpAll(() async {
    await loadRealFonts();
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDownAll(() => db.close());

  testWidgets('GOAL → clock stops → who scored? → assist', (tester) async {
    final teams = DriftTeamRepository(db);
    final team = await teams.createTeam(name: 'CP Vic');
    await teams.addMember(team.id,
        role: MemberRole.player, name: 'Marc', number: 7);
    await teams.addMember(team.id,
        role: MemberRole.player, name: 'Pau', number: 10);
    await teams.addMember(team.id, role: MemberRole.coach, name: 'Laia');
    final repo = DriftMatchRepository(db, deviceId: 'd');
    final m = await repo.createMatch(
        sport: rollerHockey.id,
        format: rollerHockey.defaultFormat,
        homeName: 'CP Vic',
        homeTeamId: team.id);
    final c = MatchController(
        matchId: m.id,
        deviceId: 'd',
        repository: repo,
        clock: const SystemClock());
    await c.startMatch();

    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceIdProvider.overrideWithValue('d'),
      ],
      child: MaterialApp(
        theme: buildPistakTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MatchScreen(matchId: m.id),
      ),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    await tester.tap(find.text('GOAL HOME'));
    await settle();
    expect(find.text('Who scored?'), findsOneWidget);
    expect(find.text('Laia'), findsNothing, reason: 'coaches are not offered');
    await tester.tap(find.text('#7 Marc'));
    await settle();

    expect(find.text('Assist?'), findsOneWidget);
    expect(find.text('#7 Marc'), findsNothing, reason: 'scorer not offered');
    await tester.tap(find.text('#10 Pau'));
    await settle();
    expect(find.text('Assist?'), findsNothing);
    expect((await c.currentState()).isClockRunning, isFalse,
        reason: 'the goal stopped the clock');

    final goal = (await repo.getEvents(m.id))
        .firstWhere((e) => e.type == EventTypes.goal);
    expect(goal.playerName, '#7 Marc');
    expect(goal.assistName, '#10 Pau');
    expect(goal.revision, greaterThan(1));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('blue card → team + player in one window', (tester) async {
    final teams = DriftTeamRepository(db);
    final team = await teams.createTeam(name: 'HC Vilassar');
    await teams.addMember(team.id,
        role: MemberRole.player, name: 'Jan', number: 4);
    final repo = DriftMatchRepository(db, deviceId: 'd');
    final m = await repo.createMatch(
        sport: rollerHockey.id,
        format: rollerHockey.defaultFormat,
        homeName: 'HC Vilassar',
        awayName: 'CP Rival',
        homeTeamId: team.id);
    await MatchController(
            matchId: m.id,
            deviceId: 'd',
            repository: repo,
            clock: const SystemClock())
        .startMatch();
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceIdProvider.overrideWithValue('d'),
      ],
      child: MaterialApp(
        theme: buildPistakTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MatchScreen(matchId: m.id),
      ),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    await tester.tap(find.byTooltip('BLUE'));
    await settle();
    expect(find.text('Who got the card?'), findsOneWidget);
    await tester.tap(find.text('#4 Jan'));
    await settle();
    final card = (await repo.getEvents(m.id))
        .firstWhere((e) => e.type == EventTypes.card);
    expect(card.team, TeamSide.home);
    expect(card.playerName, '#4 Jan');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets(
      '10th foul → direct free hit → who shoots (no assist); '
      'timeout asks 1\' or 30\'\'', (tester) async {
    final teams = DriftTeamRepository(db);
    final team = await teams.createTeam(name: 'CH Vilassar');
    await teams.addMember(team.id,
        role: MemberRole.player, name: 'Nil', number: 9);
    await teams.addMember(team.id,
        role: MemberRole.player, name: 'Ot', number: 5);
    final repo = DriftMatchRepository(db, deviceId: 'd');
    final m = await repo.createMatch(
        sport: rollerHockey.id,
        format: rollerHockey.defaultFormat.copyWith(stopClockOnEvents: false),
        homeName: 'CH Vilassar',
        homeTeamId: team.id);
    final c = MatchController(
        matchId: m.id,
        deviceId: 'd',
        repository: repo,
        clock: const SystemClock());
    await c.startMatch();
    for (var i = 0; i < 9; i++) {
      await c.foul(TeamSide.away);
    }

    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceIdProvider.overrideWithValue('d'),
      ],
      child: MaterialApp(
        theme: buildPistakTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MatchScreen(matchId: m.id),
      ),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    expect(find.textContaining('9/10'), findsOneWidget);
    await tester.tap(find.text('FOUL AWAY'));
    await settle();
    expect(find.text('Direct free hit for CH Vilassar'), findsOneWidget);
    // Who shoots is chosen in the same window, before GOAL / MISSED.
    expect(find.text('Who took it?'), findsOneWidget);
    await tester.tap(find.text('#9 Nil'));
    await settle();
    await tester.tap(find.text('GOAL'));
    await settle();
    expect(find.text('Who took it?'), findsNothing, reason: 'no 2nd question');
    expect(find.text('Assist?'), findsNothing,
        reason: 'no assist on a free hit');
    final goal = (await repo.getEvents(m.id))
        .firstWhere((e) => e.type == EventTypes.goal);
    expect(goal.team, TeamSide.home);
    expect(goal.shotKind, ShotKinds.freeHit);
    expect(goal.playerName, '#9 Nil');
    expect(find.textContaining('10/10'), findsOneWidget);

    // Timeout: both lengths left → choose.
    await tester.tap(find.text('TIMEOUT HOME'));
    await settle();
    expect(find.text('Which timeout?'), findsOneWidget);
    await tester.tap(find.text("30''"));
    await settle();
    final s = await c.currentState();
    expect(s.activeTimeout?.duration, const Duration(seconds: 30));
    expect(find.text('TIMEOUT · CH VILASSAR'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
