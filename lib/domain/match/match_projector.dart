import '../sport/match_format.dart';
import 'match_event.dart';
import 'match_state.dart';

/// Rebuilds the full match state (clock, score, stats) from its events.
///
/// Pure function: same events → same state. Tolerant: invalid transitions
/// (e.g. pausing a stopped clock) are ignored and reported in
/// [MatchState.anomalies] instead of throwing, so a single odd event can
/// never make a match unreadable.
class MatchProjector {
  const MatchProjector();

  MatchState project(MatchFormat format, Iterable<MatchEvent> events) {
    final state = MatchState(format);
    final active = events.where((e) => !e.isVoided).toList()
      ..sort(compareEvents);
    for (final e in active) {
      _apply(state, e);
      // The main event of the last action (a goal, not the automatic pause
      // it caused): events of one action share its actionId.
      if (state.lastEvent?.actionId != e.actionId) state.lastEvent = e;
    }
    return state;
  }

  void _apply(MatchState s, MatchEvent e) {
    final ts = e.timestamp;
    switch (e.type) {
      case EventTypes.matchStart:
        if (s.matchStartedAt == null) {
          s.matchStartedAt = ts;
        } else {
          s.anomalies.add('duplicate MATCH_START ${e.id}');
        }

      case EventTypes.periodStart:
        if (s.phase == MatchPhase.notStarted ||
            s.phase == MatchPhase.periodEnded ||
            s.phase == MatchPhase.onBreak) {
          final n = e.period > 0 ? e.period : s.period + 1;
          s.matchStartedAt ??= ts;
          s.period = n;
          s.elapsedAnchor = Duration.zero;
          s.runningSince = ts;
          s.phase = MatchPhase.running;
          s.periodStartedAt[n] = ts;
          s.breakStartedAt = null;
          s.activeTimeout = null;
        } else {
          s.anomalies.add('PERIOD_START ignored in ${s.phase} ${e.id}');
        }

      case EventTypes.clockPause:
        if (s.phase == MatchPhase.running) {
          _stopClock(s, ts);
          s.phase = MatchPhase.paused;
          s.pauses++;
        } else {
          s.anomalies.add('CLOCK_PAUSE ignored in ${s.phase} ${e.id}');
        }

      case EventTypes.clockResume:
        if (s.phase == MatchPhase.paused) {
          s.runningSince = ts;
          s.phase = MatchPhase.running;
          s.activeTimeout = null;
        } else {
          s.anomalies.add('CLOCK_RESUME ignored in ${s.phase} ${e.id}');
        }

      case EventTypes.clockAdjust:
        {
          final ms = (e.metadata[MetaKeys.periodElapsedMs] as num?)?.toInt();
          if (ms != null &&
              ms >= 0 &&
              (s.phase == MatchPhase.running ||
                  s.phase == MatchPhase.paused ||
                  s.phase == MatchPhase.periodEnded)) {
            s.elapsedAnchor = Duration(milliseconds: ms);
            if (s.phase == MatchPhase.running) s.runningSince = ts;
          } else {
            s.anomalies.add('CLOCK_ADJUST ignored ${e.id}');
          }
        }

      case EventTypes.periodEnd:
        if (s.phase == MatchPhase.running || s.phase == MatchPhase.paused) {
          if (s.phase == MatchPhase.running) _stopClock(s, ts);
          s.completedPlayed += s.elapsedAnchor;
          s.phase = MatchPhase.periodEnded;
          s.periodEndedAt[s.period] = ts;
          s.activeTimeout = null;
        } else {
          s.anomalies.add('PERIOD_END ignored in ${s.phase} ${e.id}');
        }

      case EventTypes.breakStart:
        if (s.phase == MatchPhase.periodEnded) {
          s.phase = MatchPhase.onBreak;
          s.breakStartedAt = ts;
        } else {
          s.anomalies.add('BREAK_START ignored in ${s.phase} ${e.id}');
        }

      case EventTypes.matchEnd:
        if (s.phase == MatchPhase.finished) {
          s.anomalies.add('duplicate MATCH_END ${e.id}');
        } else {
          if (s.phase == MatchPhase.running) _stopClock(s, ts);
          if (s.phase == MatchPhase.running || s.phase == MatchPhase.paused) {
            s.periodEndedAt[s.period] = ts;
            s.completedPlayed += s.elapsedAnchor;
          }
          s.phase = MatchPhase.finished;
          s.matchEndedAt = ts;
          s.breakStartedAt = null;
          s.activeTimeout = null;
        }

      case EventTypes.goal:
        {
          final team = e.team;
          if (team != null) {
            s.tally(team).goals++;
            if (e.shotKind != null) {
              s.tally(team).recordShot(e.shotKind, scored: true);
            }
          } else {
            s.anomalies.add('GOAL without team ${e.id}');
          }
        }

      case EventTypes.shot:
        {
          final team = e.team;
          if (team != null) s.tally(team).recordShot(e.shotKind, scored: false);
        }

      case EventTypes.save:
        {
          final team = e.team;
          if (team != null) s.tally(team).saves++;
        }

      case EventTypes.foul:
        {
          final team = e.team;
          if (team != null) {
            final t = s.tally(team);
            t.foulsByPeriod[e.period] = t.foulsIn(e.period) + 1;
          }
        }

      case EventTypes.card:
        {
          final color = e.subtype ?? 'unknown';
          final team = e.team;
          final map = team == null ? s.unassignedCards : s.tally(team).cards;
          map[color] = (map[color] ?? 0) + 1;
          if (team != null && color == CardColors.blue && s.period > 0) {
            s.exclusions.add(Exclusion(
              team,
              s.completedPlayed + s.periodElapsedAt(ts),
              s.format.exclusionDuration,
              e.id,
            ));
          }
        }

      case EventTypes.timeout:
        {
          final team = e.team;
          if (team != null) {
            final t = s.tally(team);
            t.timeoutsByPeriod[e.period] = t.timeoutsIn(e.period) + 1;
            final ms = (e.metadata[MetaKeys.durationMs] as num?)?.toInt();
            final length = ms == null || ms <= 0
                ? s.format.timeoutDuration
                : Duration(milliseconds: ms);
            (t.timeoutLengthsByPeriod[e.period] ??= []).add(length);
            if (s.isInPlay) s.activeTimeout = ActiveTimeout(team, ts, length);
          }
        }

      case EventTypes.timeoutEnd:
        if (s.activeTimeout != null) {
          s.activeTimeout = null;
        } else {
          s.anomalies.add('TIMEOUT_END without active timeout ${e.id}');
        }

      case EventTypes.incident:
        s.incidents++;

      case EventTypes.shootoutStart:
        if (s.phase == MatchPhase.finished || s.phase == MatchPhase.shootout) {
          s.anomalies.add('SHOOTOUT_START ignored in ${s.phase} ${e.id}');
        } else {
          if (s.phase == MatchPhase.running) _stopClock(s, ts);
          if (s.isInPlay) {
            s.periodEndedAt[s.period] = ts;
            s.completedPlayed += s.elapsedAnchor;
          }
          s.phase = MatchPhase.shootout;
          s.breakStartedAt = null;
          s.activeTimeout = null;
        }

      case EventTypes.shootoutAttempt:
        {
          final team = e.team;
          if (team != null) {
            final t = s.tally(team);
            t.shootoutAttempts++;
            if (e.subtype == ShootoutResults.scored) t.shootoutScored++;
          }
        }

      default:
        // Unknown types (newer app version / other sport) are preserved in
        // the log but don't affect the core projection.
        break;
    }
  }

  void _stopClock(MatchState s, DateTime ts) {
    s.elapsedAnchor = s.periodElapsedAt(ts);
    s.runningSince = null;
  }
}
