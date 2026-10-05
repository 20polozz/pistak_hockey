import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/core/time_format.dart';
import 'package:pistak/domain/match/event_factory.dart';
import 'package:pistak/domain/match/match_event.dart';
import 'package:pistak/domain/match/match_state.dart';
import 'package:pistak/domain/sport/match_format.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';

import 'match_clock_test.dart' show Sim;

const short = MatchFormat(
  id: 't',
  name: '2 × 10',
  periods: 2,
  periodDuration: Duration(minutes: 10),
  breakDuration: Duration(minutes: 2),
  foulLimit: 10,
  overtimePeriods: 2,
  overtimeDuration: Duration(minutes: 3),
  allowShootout: true,
);

void playRegulation(Sim sim) {
  sim.run((f, s) => f.startMatch(s));
  sim.waitMs(10);
  sim.run((f, s) => f.endPeriod(s));
  sim.run((f, s) => f.startNextPeriod(s));
  sim.waitMs(10);
}

void main() {
  group('Blue card exclusion', () {
    test('counts only played time and expires after 2 minutes', () {
      final sim = Sim();
      sim.run((f, s) => f.startMatch(s));
      sim.waitMs(5);
      sim.run((f, s) => f.card(s, CardColors.blue, team: TeamSide.away));
      sim.waitMs(1);
      var active = sim.state.activeExclusionsAt(sim.clock.now());
      expect(active.single.$1.team, TeamSide.away);
      expect(active.single.$2, const Duration(minutes: 1));
      // A 5-minute pause does not consume the exclusion.
      sim.run((f, s) => f.pause(s));
      sim.waitMs(5);
      expect(sim.state.activeExclusionsAt(sim.clock.now()).single.$2,
          const Duration(minutes: 1));
      sim.run((f, s) => f.resume(s));
      sim.waitMs(1);
      expect(sim.state.activeExclusionsAt(sim.clock.now()), isEmpty);
    });

    test('unassigned blue card starts no exclusion until a team is set', () {
      final sim = Sim();
      sim.run((f, s) => f.startMatch(s));
      final c = sim.run((f, s) => f.card(s, CardColors.blue)).single;
      expect(sim.state.exclusions, isEmpty);
      sim.events[sim.events.indexOf(c)] = c.copyWith(team: TeamSide.home);
      expect(sim.state.activeExclusionsAt(sim.clock.now(), team: TeamSide.home),
          hasLength(1));
    });

    test('exclusion carries over the half-time break', () {
      final sim = Sim(format: short);
      sim.run((f, s) => f.startMatch(s));
      sim.waitMs(9);
      sim.run((f, s) => f.card(s, CardColors.blue, team: TeamSide.home));
      sim.waitMs(1);
      sim.run((f, s) => f.endPeriod(s));
      sim.waitMs(2); // break
      sim.run((f, s) => f.startNextPeriod(s));
      expect(sim.state.activeExclusionsAt(sim.clock.now()).single.$2,
          const Duration(minutes: 1));
    });
  });

  group('Foul limit', () {
    test('near and reached flags per period', () {
      final sim = Sim(format: short);
      sim.run((f, s) => f.startMatch(s));
      for (var i = 0; i < 9; i++) {
        sim.run((f, s) => f.foul(s, TeamSide.home));
      }
      expect(sim.state.foulLimitNear(TeamSide.home), isTrue);
      expect(sim.state.foulLimitReached(TeamSide.home), isFalse);
      sim.run((f, s) => f.foul(s, TeamSide.home));
      expect(sim.state.foulLimitReached(TeamSide.home), isTrue);
      expect(sim.state.foulLimitReached(TeamSide.away), isFalse);
      // New period: counter starts again.
      sim.waitMs(10);
      sim.run((f, s) => f.endPeriod(s));
      sim.run((f, s) => f.startNextPeriod(s));
      expect(sim.state.foulLimitReached(TeamSide.home), isFalse);
    });

    test('no limit configured → never flagged', () {
      final sim = Sim(format: short.copyWith(clearFoulLimit: true));
      sim.run((f, s) => f.startMatch(s));
      for (var i = 0; i < 20; i++) {
        sim.run((f, s) => f.foul(s, TeamSide.away));
      }
      expect(sim.state.foulLimitReached(TeamSide.away), isFalse);
    });
  });

  group('Overtime', () {
    test('last period → overtime break → OT1 starts at 20:00', () {
      final sim = Sim(format: short);
      playRegulation(sim);
      final end =
          sim.run((f, s) => f.endPeriod(s, then: PeriodEndChoice.overtime));
      expect(end.map((e) => e.type),
          [EventTypes.periodEnd, EventTypes.breakStart]);
      expect(end.first.metadata[MetaKeys.regularPeriods], 2);
      sim.waitMs(2);
      final ot = sim.run((f, s) => f.startNextPeriod(s)).single;
      expect(ot.period, 3);
      expect(formatMatchTime(ot.matchTime), '20:00');
      expect(sim.state.isOvertime, isTrue);
      sim.waitMs(3);
      expect(sim.shown, '23:00');
      expect(sim.state.isOvertimeAt(sim.clock.now()), isFalse);
      sim.run((f, s) => f.endPeriod(s, then: PeriodEndChoice.overtime));
      sim.run((f, s) => f.startNextPeriod(s));
      sim.waitMs(3);
      expect(sim.shown, '26:00');
      // No more overtime periods: overtime choice falls back to end of match.
      final last =
          sim.run((f, s) => f.endPeriod(s, then: PeriodEndChoice.overtime));
      expect(last.last.type, EventTypes.matchEnd);
      expect(sim.state.isFinished, isTrue);
    });

    test('overtime not configured → end of match', () {
      final sim = Sim(); // default 2×25 has overtime in presets…
      final sim2 = Sim(format: short.copyWith(overtimePeriods: 0));
      playRegulation(sim2);
      final end =
          sim2.run((f, s) => f.endPeriod(s, then: PeriodEndChoice.overtime));
      expect(end.last.type, EventTypes.matchEnd);
      expect(sim.state.phase, MatchPhase.notStarted);
    });
  });

  group('Penalty shoot-out', () {
    test('from the last period, attempts are tallied, then final', () {
      final sim = Sim(format: short);
      playRegulation(sim);
      final ev =
          sim.run((f, s) => f.endPeriod(s, then: PeriodEndChoice.shootout));
      expect(ev.last.type, EventTypes.shootoutStart);
      expect(sim.state.phase, MatchPhase.shootout);
      final clock = sim.shown;
      sim.waitMs(4);
      expect(sim.shown, clock, reason: 'clock stopped during shoot-out');
      sim.run((f, s) => f.shootoutAttempt(s, TeamSide.home, scored: true));
      sim.run((f, s) => f.shootoutAttempt(s, TeamSide.away, scored: false));
      sim.run((f, s) => f.shootoutAttempt(s, TeamSide.home, scored: true));
      final st = sim.state;
      expect(st.home.shootoutScored, 2);
      expect(st.home.shootoutAttempts, 2);
      expect(st.away.shootoutScored, 0);
      expect(st.away.shootoutAttempts, 1);
      expect(st.home.goals, 0, reason: 'penalties are not match goals');
      expect(st.hadShootout, isTrue);
      sim.run((f, s) => f.endMatch(s));
      expect(sim.state.isFinished, isTrue);
    });

    test('shoot-out after an overtime break', () {
      final sim = Sim(format: short);
      playRegulation(sim);
      sim.run((f, s) => f.endPeriod(s, then: PeriodEndChoice.overtime));
      expect(sim.run((f, s) => f.startShootout(s)).single.type,
          EventTypes.shootoutStart);
    });

    test('not allowed by the format → no shoot-out', () {
      final sim = Sim(format: short.copyWith(allowShootout: false));
      playRegulation(sim);
      final ev =
          sim.run((f, s) => f.endPeriod(s, then: PeriodEndChoice.shootout));
      expect(ev.last.type, EventTypes.matchEnd);
    });
  });

  test('old saved formats (without new keys) still load', () {
    final legacy = {
      'id': 'x',
      'name': 'x',
      'periods': 2,
      'periodDurationMs': 1500000,
      'breakDurationMs': 600000,
    };
    final f = MatchFormat.fromJson(legacy);
    expect(f.foulLimit, isNull);
    expect(f.overtimePeriods, 0);
    expect(f.allowShootout, isFalse);
    expect(f.exclusionDuration, const Duration(minutes: 2));
    expect(rollerHockey.defaultFormat.foulLimit, 10);
  });
}
