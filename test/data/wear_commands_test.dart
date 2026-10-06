import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/core/clock.dart';
import 'package:pistak/data/db/app_database.dart';
import 'package:pistak/data/repositories/drift_match_repository.dart';
import 'package:pistak/domain/match/match_event.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';
import 'package:pistak/ui/match_controller.dart';
import 'package:pistak/wear/wear_commands.dart';

/// Continuous clock: these tests are about other things than the automatic
/// stops of effective time (see test/domain/effective_time_test.dart).
final continuousTime =
    rollerHockey.defaultFormat.copyWith(stopClockOnEvents: false);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DriftMatchRepository repo;
  late FakeClock clock;
  late WearCommandProcessor wear;
  final controllers = <String, MatchController>{};

  MatchController ctl(String id) => controllers.putIfAbsent(
      id,
      () => MatchController(
          matchId: id, deviceId: 'phone', repository: repo, clock: clock));

  WearCommand cmd(String id, String c,
          {String? team, String? color, DateTime? at}) =>
      WearCommand.tryParse(jsonEncode({
        'id': id,
        'cmd': c,
        if (team != null) 'team': team,
        if (color != null) 'color': color,
        'at': (at ?? clock.now()).millisecondsSinceEpoch,
      }))!;

  setUp(() {
    clock = FakeClock(DateTime.utc(2026, 10, 12, 18));
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftMatchRepository(db, deviceId: 'phone', clock: clock);
    controllers.clear();
    wear = WearCommandProcessor(
        repository: repo, controllerFor: ctl, clock: clock);
  });

  tearDown(() => db.close());

  Future<String> liveMatch() async {
    final m =
        await repo.createMatch(sport: rollerHockey.id, format: continuousTime);
    await ctl(m.id).startMatch();
    return m.id;
  }

  test('without a match in progress commands are not applied', () async {
    expect(await wear.process(cmd('w1', 'goal', team: 'home')),
        WearOutcome.noActiveMatch);
  });

  test('a watch goal is stored once even if delivered three times', () async {
    final id = await liveMatch();
    clock.advance(const Duration(minutes: 2));
    final tapAt = clock.now();
    final goal = cmd('w-goal', 'goal', team: 'away', at: tapAt);
    clock.advance(const Duration(seconds: 30)); // arrives later
    expect(await wear.process(goal), WearOutcome.applied);
    expect(await wear.process(goal), WearOutcome.duplicate);
    expect(await wear.process(goal), WearOutcome.duplicate);

    final goals = (await repo.getEvents(id))
        .where((e) => e.type == EventTypes.goal)
        .toList();
    expect(goals, hasLength(1));
    expect(goals.single.team, TeamSide.away);
    expect(goals.single.timestamp, tapAt, reason: 'tap time from the watch');
    expect(goals.single.matchTime, const Duration(minutes: 2));
    expect((await repo.getMatch(id))!.awayScore, 1);
  });

  test('multi-event commands (timeout) replay without duplicates', () async {
    final id = await liveMatch();
    clock.advance(const Duration(minutes: 5));
    final tm = cmd('w-tm', 'timeout', team: 'home');
    await wear.process(tm);
    final before = (await repo.getEvents(id)).length;
    expect(await wear.process(tm), WearOutcome.duplicate);
    expect((await repo.getEvents(id)).length, before);

    // RESUME on the watch during a timeout ends the timeout.
    clock.advance(const Duration(minutes: 1));
    await wear.process(cmd('w-res', 'resume'));
    final s = await ctl(id).currentState();
    expect(s.activeTimeout, isNull);
    expect(s.isClockRunning, isTrue);
  });

  test('cards, fouls, pause and incident from the watch', () async {
    final id = await liveMatch();
    clock.advance(const Duration(minutes: 1));
    await wear.process(cmd('a', 'card', color: CardColors.blue));
    await wear.process(cmd('b', 'foul', team: 'home'));
    await wear.process(cmd('c', 'pause'));
    await wear.process(cmd('d', 'incident'));
    expect(await wear.process(cmd('e', 'card', color: 'purple')),
        WearOutcome.ignored);
    expect(await wear.process(cmd('f', 'goal')), WearOutcome.ignored,
        reason: 'goal without team');
    final s = await ctl(id).currentState();
    expect(s.home.fouls, 1);
    expect(s.isClockRunning, isFalse);
    expect(s.incidents, 1);
    expect(s.unassignedCards[CardColors.blue], 1);
  });

  test('a watch clock ahead of the phone never stamps future events', () async {
    final id = await liveMatch();
    final future = clock.now().add(const Duration(minutes: 10));
    await wear.process(cmd('fut', 'goal', team: 'home', at: future));
    final goal =
        (await repo.getEvents(id)).firstWhere((e) => e.type == EventTypes.goal);
    expect(goal.timestamp, clock.now());
  });

  test('malformed payloads are ignored', () {
    expect(WearCommand.tryParse('not json'), isNull);
    expect(WearCommand.tryParse('{"cmd":"goal","at":1}'), isNull);
    expect(WearCommand.tryParse('[]'), isNull);
  });

  test('scoreboard state for the watch', () async {
    final id = await liveMatch();
    clock.advance(const Duration(minutes: 3));
    await ctl(id).goal(TeamSide.home);
    final s = await ctl(id).currentState();
    final json = wearScoreState(s, clock.now());
    expect(json['home'], 1);
    expect(json['away'], 0);
    expect(json['label'], 'P1');
    expect(json['running'], isTrue);
    expect(json['matchMs'], const Duration(minutes: 3).inMilliseconds);
    expect(wearScoreState(null, clock.now())['label'], '—');
  });
}
