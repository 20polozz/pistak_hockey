import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/core/clock.dart';
import 'package:pistak/core/ids.dart';
import 'package:pistak/core/time_format.dart';
import 'package:pistak/domain/match/event_factory.dart';
import 'package:pistak/domain/match/match_event.dart';
import 'package:pistak/domain/match/match_projector.dart';
import 'package:pistak/domain/match/match_state.dart';
import 'package:pistak/domain/sport/match_format.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';

/// In-memory match simulator: commands → events → projected state.
class Sim {
  Sim({MatchFormat? format})
      : format = format ?? rollerHockey.defaultFormat,
        clock = FakeClock(DateTime.utc(2026, 10, 12, 16, 30)) {
    ef = EventFactory(
      matchId: 'm1',
      deviceId: 'd1',
      clock: clock,
      ids: SequentialIdGenerator('e'),
    );
  }

  final MatchFormat format;
  final FakeClock clock;
  late final EventFactory ef;
  final events = <MatchEvent>[];
  static const projector = MatchProjector();

  MatchState get state => projector.project(format, events);

  List<MatchEvent> run(
      List<MatchEvent> Function(EventFactory f, MatchState s) cmd) {
    final produced = cmd(ef, state);
    events.addAll(produced);
    return produced;
  }

  void wait(Duration d) => clock.advance(d);
  void waitMs(int minutes, [int seconds = 0]) =>
      wait(Duration(minutes: minutes, seconds: seconds));

  Duration get time => state.matchTimeAt(clock.now());
  String get shown => formatMatchTime(time);

  /// Same semantics as the repository: void every event of the last action.
  void undo() {
    final last = events.lastWhere((e) => !e.isVoided);
    for (var i = 0; i < events.length; i++) {
      if (events[i].actionId == last.actionId && !events[i].isVoided) {
        events[i] = events[i].copyWith(voidedAt: clock.now());
      }
    }
  }
}

void main() {
  group('Clock', () {
    test('not started shows 00:00 and does not run', () {
      final sim = Sim();
      sim.waitMs(5);
      expect(sim.state.phase, MatchPhase.notStarted);
      expect(sim.shown, '00:00');
    });

    test('start runs from real timestamps (no ticking counter)', () {
      final sim = Sim();
      final ev = sim.run((f, s) => f.startMatch(s));
      expect(ev.map((e) => e.type),
          [EventTypes.matchStart, EventTypes.periodStart]);
      sim.waitMs(8, 42);
      expect(sim.state.phase, MatchPhase.running);
      expect(sim.state.period, 1);
      expect(sim.shown, '08:42');
    });

    test('pause freezes the time and resume continues', () {
      final sim = Sim();
      sim.run((f, s) => f.startMatch(s));
      sim.waitMs(5);
      sim.run((f, s) => f.pause(s));
      sim.waitMs(3); // paused: must not count
      expect(sim.shown, '05:00');
      expect(sim.state.phase, MatchPhase.paused);
      sim.run((f, s) => f.resume(s));
      sim.waitMs(1);
      expect(sim.shown, '06:00');
      expect(sim.state.pauses, 1);
    });

    test('invalid clock transitions are rejected (empty list)', () {
      final sim = Sim();
      expect(sim.run((f, s) => f.pause(s)), isEmpty);
      expect(sim.run((f, s) => f.resume(s)), isEmpty);
      expect(sim.run((f, s) => f.endPeriod(s)), isEmpty);
      sim.run((f, s) => f.startMatch(s));
      expect(sim.run((f, s) => f.startMatch(s)), isEmpty);
      expect(sim.run((f, s) => f.resume(s)), isEmpty);
    });

    test('full match: halves, break, cumulative time, final', () {
      final sim = Sim(); // 2 × 25
      sim.run((f, s) => f.startMatch(s));
      sim.waitMs(25);
      final end1 = sim.run((f, s) => f.endPeriod(s));
      expect(end1.map((e) => e.type),
          [EventTypes.periodEnd, EventTypes.breakStart]);
      expect(formatMatchTime(end1.first.matchTime), '25:00');
      expect(sim.state.phase, MatchPhase.onBreak);

      sim.waitMs(10); // break does not count as match time
      expect(sim.shown, '25:00');
      expect(sim.state.breakElapsedAt(sim.clock.now()),
          const Duration(minutes: 10));

      final start2 = sim.run((f, s) => f.startNextPeriod(s));
      expect(start2.single.period, 2);
      expect(formatMatchTime(start2.single.matchTime), '25:00');
      sim.waitMs(18, 21);
      final goal = sim.run((f, s) => f.goal(s, TeamSide.away)).single;
      expect(formatMatchTime(goal.matchTime), '43:21');
      expect(goal.period, 2);

      sim.waitMs(6, 39);
      final end = sim.run((f, s) => f.endPeriod(s));
      expect(
          end.map((e) => e.type), [EventTypes.periodEnd, EventTypes.matchEnd]);
      expect(formatMatchTime(end.last.matchTime), '50:00');

      final st = sim.state;
      expect(st.phase, MatchPhase.finished);
      expect(st.matchStartedAt, DateTime.utc(2026, 10, 12, 16, 30));
      expect(st.matchEndedAt, DateTime.utc(2026, 10, 12, 17, 30));
      expect(st.realDuration, const Duration(minutes: 60));
      expect(st.periodStartedAt.keys, [1, 2]);
      expect(st.periodEndedAt.keys, [1, 2]);
      // Nothing can be started after the final.
      expect(sim.run((f, s) => f.startNextPeriod(s)), isEmpty);
    });

    test('formats are configurable (2 × 15)', () {
      final sim = Sim(format: rollerHockey.formatById('rh_2x15'));
      sim.run((f, s) => f.startMatch(s));
      sim.waitMs(15);
      sim.run((f, s) => f.endPeriod(s));
      sim.run((f, s) => f.startNextPeriod(s));
      sim.waitMs(1);
      expect(sim.shown, '16:00');
    });

    test('3 periods × 10 min with two breaks', () {
      final sim = Sim(
          format: const MatchFormat(
              id: 'c3',
              name: '3 × 10',
              periods: 3,
              periodDuration: Duration(minutes: 10),
              breakDuration: Duration(minutes: 2)));
      sim.run((f, s) => f.startMatch(s));
      for (var p = 1; p <= 2; p++) {
        sim.waitMs(10);
        final end = sim.run((f, s) => f.endPeriod(s));
        expect(end.last.type, EventTypes.breakStart);
        sim.waitMs(2);
        sim.run((f, s) => f.startNextPeriod(s));
      }
      expect(sim.state.period, 3);
      sim.waitMs(4);
      expect(sim.shown, '24:00');
      sim.waitMs(6);
      final end = sim.run((f, s) => f.endPeriod(s));
      expect(end.last.type, EventTypes.matchEnd);
      expect(formatMatchTime(end.last.matchTime), '30:00');
    });

    test('overtime of a period is flagged, not cut', () {
      final sim = Sim();
      sim.run((f, s) => f.startMatch(s));
      sim.waitMs(25, 30);
      expect(sim.shown, '25:30');
      expect(sim.state.isOvertimeAt(sim.clock.now()), isTrue);
    });

    test('clock adjust sets the period elapsed time', () {
      final sim = Sim();
      sim.run((f, s) => f.startMatch(s));
      sim.waitMs(10);
      sim.run(
          (f, s) => f.adjustClock(s, const Duration(minutes: 9, seconds: 30)));
      expect(sim.shown, '09:30');
      sim.waitMs(1);
      expect(sim.shown, '10:30');
    });

    test('app killed / screen off / reboot: state rebuilt from stored events',
        () {
      final sim = Sim();
      sim.run((f, s) => f.startMatch(s));
      sim.waitMs(3);
      sim.run((f, s) => f.goal(s, TeamSide.home));
      // Persist (JSON round-trip), then 7 minutes with the app dead.
      final stored = sim.events.map((e) => e.toJson()).toList();
      sim.waitMs(7);
      final restored = stored.map(MatchEvent.fromJson).toList();
      final st = const MatchProjector().project(sim.format, restored);
      expect(formatMatchTime(st.matchTimeAt(sim.clock.now())), '10:00');
      expect(st.home.goals, 1);
      expect(st.isClockRunning, isTrue);
    });

    test('a clock that goes backwards never yields negative time', () {
      final sim = Sim();
      sim.run((f, s) => f.startMatch(s));
      sim.wait(const Duration(minutes: -2));
      expect(sim.shown, '00:00');
    });
  });

  group('Timeouts', () {
    test('timeout pauses the clock when the format says so', () {
      final sim = Sim();
      sim.run((f, s) => f.startMatch(s));
      sim.waitMs(12, 14);
      final ev = sim.run((f, s) => f.timeout(s, TeamSide.home));
      expect(
          ev.map((e) => e.type), [EventTypes.timeout, EventTypes.clockPause]);
      expect(ev.first.actionId, ev.last.actionId);
      expect(ev.last.subtype, PauseReasons.timeout);
      sim.waitMs(0, 20);
      final st = sim.state;
      expect(st.phase, MatchPhase.paused);
      expect(st.home.timeoutsIn(1), 1);
      expect(st.activeTimeout?.team, TeamSide.home);
      expect(
          st.timeoutRemainingAt(sim.clock.now()), const Duration(seconds: 40));
      expect(sim.shown, '12:14');
      sim.run((f, s) => f.resume(s));
      expect(sim.state.activeTimeout, isNull);
    });

    test('timeout does not touch the clock when configured so', () {
      final sim = Sim(
          format:
              rollerHockey.defaultFormat.copyWith(stopClockOnTimeout: false));
      sim.run((f, s) => f.startMatch(s));
      final ev = sim.run((f, s) => f.timeout(s, TeamSide.away));
      expect(ev.single.type, EventTypes.timeout);
      expect(sim.state.isClockRunning, isTrue);
    });

    test('end of timeout is recorded and restarts the clock', () {
      final sim = Sim();
      sim.run((f, s) => f.startMatch(s));
      sim.waitMs(10);
      sim.run((f, s) => f.timeout(s, TeamSide.away));
      sim.waitMs(1);
      expect(sim.shown, '10:00');
      final end = sim.run((f, s) => f.endTimeout(s));
      expect(end.map((e) => e.type),
          [EventTypes.timeoutEnd, EventTypes.clockResume]);
      expect(end.first.team, TeamSide.away);
      expect(end.last.subtype, ResumeReasons.timeoutEnd);
      final st = sim.state;
      expect(st.activeTimeout, isNull);
      expect(st.isClockRunning, isTrue);
      expect(st.away.timeouts, 1);
      sim.waitMs(2);
      expect(sim.shown, '12:00');
      // No active timeout → nothing to end.
      expect(sim.run((f, s) => f.endTimeout(s)), isEmpty);
    });

    test('end of timeout without clock stop only closes the timeout', () {
      final sim = Sim(
          format:
              rollerHockey.defaultFormat.copyWith(stopClockOnTimeout: false));
      sim.run((f, s) => f.startMatch(s));
      sim.run((f, s) => f.timeout(s, TeamSide.home));
      expect(sim.state.activeTimeout, isNotNull);
      final end = sim.run((f, s) => f.endTimeout(s));
      expect(end.single.type, EventTypes.timeoutEnd);
      expect(sim.state.activeTimeout, isNull);
      expect(sim.state.isClockRunning, isTrue);
    });

    test('custom timeout duration drives the countdown', () {
      final sim = Sim(
          format: rollerHockey.defaultFormat
              .copyWith(timeoutDuration: const Duration(seconds: 30)));
      sim.run((f, s) => f.startMatch(s));
      sim.run((f, s) => f.timeout(s, TeamSide.home));
      sim.wait(const Duration(seconds: 10));
      expect(sim.state.timeoutRemainingAt(sim.clock.now()),
          const Duration(seconds: 20));
    });

    test('undo of a timeout removes the timeout AND its pause', () {
      final sim = Sim();
      sim.run((f, s) => f.startMatch(s));
      sim.waitMs(5);
      sim.run((f, s) => f.timeout(s, TeamSide.home));
      sim.waitMs(1);
      sim.undo();
      final st = sim.state;
      expect(st.isClockRunning, isTrue);
      expect(st.home.timeouts, 0);
      expect(sim.shown, '06:00');
    });
  });

  group('Recording events', () {
    test('goals update the score with exact time and period', () {
      final sim = Sim();
      sim.run((f, s) => f.startMatch(s));
      sim.waitMs(3, 42);
      final g = sim.run((f, s) => f.goal(s, TeamSide.home)).single;
      expect(g.type, EventTypes.goal);
      expect(g.team, TeamSide.home);
      expect(g.period, 1);
      expect(formatMatchTime(g.matchTime), '03:42');
      expect(g.timestamp, DateTime.utc(2026, 10, 12, 16, 33, 42));
      expect(g.syncStatus, SyncStatus.pending);
      sim.run((f, s) => f.goal(s, TeamSide.home));
      sim.run((f, s) => f.goal(s, TeamSide.away));
      expect(sim.state.home.goals, 2);
      expect(sim.state.away.goals, 1);
    });

    test('fouls are counted per team and per period', () {
      final sim = Sim();
      sim.run((f, s) => f.startMatch(s));
      for (var i = 0; i < 3; i++) {
        sim.run((f, s) => f.foul(s, TeamSide.away));
      }
      sim.run((f, s) => f.foul(s, TeamSide.home));
      sim.waitMs(25);
      sim.run((f, s) => f.endPeriod(s));
      sim.run((f, s) => f.startNextPeriod(s));
      sim.run((f, s) => f.foul(s, TeamSide.away));
      final st = sim.state;
      expect(st.away.foulsIn(1), 3);
      expect(st.away.foulsIn(2), 1);
      expect(st.away.fouls, 4);
      expect(st.home.fouls, 1);
    });

    test('cards are one-tap; the team can be assigned later', () {
      final sim = Sim();
      sim.run((f, s) => f.startMatch(s));
      final card = sim.run((f, s) => f.card(s, CardColors.blue)).single;
      expect(card.team, isNull);
      expect(sim.state.unassignedCards[CardColors.blue], 1);
      sim.events[sim.events.indexOf(card)] =
          card.copyWith(team: TeamSide.away, revision: 2);
      final st = sim.state;
      expect(st.unassignedCards[CardColors.blue], isNull);
      expect(st.away.cardsOf(CardColors.blue), 1);
      sim.run((f, s) => f.card(s, CardColors.yellow, team: TeamSide.home));
      sim.run((f, s) => f.card(s, CardColors.red, team: TeamSide.home));
      expect(sim.state.totalCards, 3);
    });

    test('incidents: written, unjustified (voice comes in phase 4)', () {
      final sim = Sim();
      sim.run((f, s) => f.startMatch(s));
      final t = sim
          .run((f, s) => f.incident(s,
              kind: IncidentKinds.text, text: '  Problema amb la pista  '))
          .single;
      expect(t.subtype, IncidentKinds.text);
      expect(t.text, 'Problema amb la pista');
      final u = sim.run((f, s) => f.incident(s)).single;
      expect(u.subtype, IncidentKinds.unjustified);
      expect(u.text, isNull);
      expect(sim.state.incidents, 2);
    });

    test('recording is never rejected, even before the start', () {
      final sim = Sim();
      final g = sim.run((f, s) => f.goal(s, TeamSide.home)).single;
      expect(g.period, 0);
      expect(g.matchTime, Duration.zero);
      expect(sim.state.home.goals, 1);
    });

    test('undo removes only the last action', () {
      final sim = Sim();
      sim.run((f, s) => f.startMatch(s));
      sim.run((f, s) => f.goal(s, TeamSide.home));
      sim.run((f, s) => f.goal(s, TeamSide.home));
      sim.undo();
      expect(sim.state.home.goals, 1);
      expect(sim.events.where((e) => e.isVoided).length, 1);
      // History is kept: the voided event still exists.
      expect(sim.events.length, 4);
    });

    test('late events (e.g. from a watch) are ordered by real time', () {
      final sim = Sim();
      sim.run((f, s) => f.startMatch(s));
      sim.waitMs(5);
      final pause = sim.run((f, s) => f.pause(s)).single;
      // A goal that happened 1 min BEFORE the pause, delivered after it.
      final goal = MatchEvent(
        id: 'watch-1',
        matchId: 'm1',
        type: EventTypes.goal,
        team: TeamSide.away,
        period: 1,
        matchTime: const Duration(minutes: 4),
        periodTime: const Duration(minutes: 4),
        timestamp: pause.timestamp.subtract(const Duration(minutes: 1)),
        createdAt: sim.clock.now(),
        updatedAt: sim.clock.now(),
        deviceId: 'watch',
        actionId: 'a-watch',
        seq: 999,
      );
      sim.events.add(goal);
      final st = sim.state;
      expect(st.away.goals, 1);
      expect(st.phase, MatchPhase.paused);
      expect(st.lastEvent?.id, pause.id);
    });
  });

  group('Serialization & formatting', () {
    test('MatchEvent JSON round-trip', () {
      final sim = Sim();
      sim.run((f, s) => f.startMatch(s));
      final e = sim
          .run(
              (f, s) => f.incident(s, kind: IncidentKinds.text, text: 'Patins'))
          .single;
      final back = MatchEvent.fromJson(e.toJson());
      expect(back.toJson(), e.toJson());
    });

    test('MatchFormat JSON round-trip', () {
      final f = rollerHockey.defaultFormat;
      expect(MatchFormat.fromJson(f.toJson()), f);
    });

    test('time formatting and parsing', () {
      expect(formatMatchTime(const Duration(minutes: 50)), '50:00');
      expect(formatMatchTime(const Duration(seconds: 522)), '08:42');
      expect(parseMatchTime('08:42'), const Duration(seconds: 522));
      expect(parseMatchTime('12'), const Duration(minutes: 12));
      expect(parseMatchTime('3:7'), const Duration(minutes: 3, seconds: 7));
      expect(parseMatchTime('1:75'), isNull);
      expect(parseMatchTime('abc'), isNull);
    });
  });
}
