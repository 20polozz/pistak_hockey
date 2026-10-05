import '../sport/match_format.dart';
import 'match_event.dart';

enum MatchPhase {
  /// Created, clock never started.
  notStarted,

  /// A period is being played and the clock runs.
  running,

  /// A period is being played but the clock is stopped.
  paused,

  /// A period ended; break not started yet (transient).
  periodEnded,

  /// Break between periods (e.g. half-time).
  onBreak,

  /// Penalty shoot-out (after the last period).
  shootout,

  /// Match finished.
  finished,
}

/// Per-team counters derived from the event log.
class TeamTally {
  TeamTally();

  int goals = 0;
  final Map<int, int> foulsByPeriod = {};
  final Map<int, int> timeoutsByPeriod = {};
  final Map<String, int> cards = {};
  int shootoutScored = 0;
  int shootoutAttempts = 0;

  int get fouls => foulsByPeriod.values.fold<int>(0, (a, b) => a + b);
  int get timeouts => timeoutsByPeriod.values.fold<int>(0, (a, b) => a + b);
  int foulsIn(int period) => foulsByPeriod[period] ?? 0;
  int timeoutsIn(int period) => timeoutsByPeriod[period] ?? 0;
  int cardsOf(String color) => cards[color] ?? 0;
}

/// A player excluded by a blue card. Counts PLAYED time (clock running),
/// so pauses and breaks don't consume it.
class Exclusion {
  const Exclusion(this.team, this.startPlayed, this.duration, this.eventId);
  final TeamSide team;
  final Duration startPlayed;
  final Duration duration;
  final String eventId;
}

class ActiveTimeout {
  const ActiveTimeout(this.team, this.startedAt);
  final TeamSide team;
  final DateTime startedAt;
}

/// Snapshot of a match computed by [MatchProjector] from its events.
///
/// The clock is NOT a counter: [periodElapsedAt] computes the time from the
/// stored timestamps, so it is always correct after the screen turns off,
/// the app is killed or the device reboots.
class MatchState {
  MatchState(this.format);

  final MatchFormat format;

  MatchPhase phase = MatchPhase.notStarted;

  /// Current period (0 before the match starts).
  int period = 0;

  /// Elapsed time in the current period at [runningSince] (or total if stopped).
  Duration elapsedAnchor = Duration.zero;

  /// Clock-running time of the periods already finished.
  Duration completedPlayed = Duration.zero;

  final List<Exclusion> exclusions = [];

  /// When the clock started running (null if stopped).
  DateTime? runningSince;

  final TeamTally home = TeamTally();
  final TeamTally away = TeamTally();

  /// Cards registered without a team yet, by colour.
  final Map<String, int> unassignedCards = {};
  int incidents = 0;
  int pauses = 0;

  DateTime? matchStartedAt;
  DateTime? matchEndedAt;
  final Map<int, DateTime> periodStartedAt = {};
  final Map<int, DateTime> periodEndedAt = {};
  DateTime? breakStartedAt;
  ActiveTimeout? activeTimeout;

  /// Last non-voided event (any type) and its action, for the undo bar.
  MatchEvent? lastEvent;

  /// Invalid transitions ignored while projecting (diagnostics).
  final List<String> anomalies = [];

  TeamTally tally(TeamSide side) => side == TeamSide.home ? home : away;

  bool get isClockRunning => phase == MatchPhase.running;
  bool get isStarted => phase != MatchPhase.notStarted;
  bool get isFinished => phase == MatchPhase.finished;
  bool get isInPlay =>
      phase == MatchPhase.running || phase == MatchPhase.paused;

  /// True from the last regulation period on (overtime included).
  bool get isLastPeriod => period >= format.periods;
  bool get isOvertime => format.isOvertimePeriod(period);
  bool get hasMoreRegularPeriods => period < format.periods;
  bool get canPlayOvertime => period < format.totalPeriods;
  bool get isShootout => phase == MatchPhase.shootout;
  bool get hadShootout =>
      home.shootoutAttempts + away.shootoutAttempts > 0 || isShootout;

  /// Total clock-running time of the match at [now].
  Duration playedAt(DateTime now) =>
      period <= 0 ? Duration.zero : completedPlayed + periodElapsedAt(now);

  /// Exclusions still running at [now], with their remaining time.
  List<(Exclusion, Duration)> activeExclusionsAt(DateTime now,
      {TeamSide? team}) {
    final played = playedAt(now);
    return [
      for (final x in exclusions)
        if (team == null || x.team == team)
          if (x.duration - (played - x.startPlayed) > Duration.zero)
            (x, x.duration - (played - x.startPlayed)),
    ];
  }

  /// Fouls of [team] in the current period reached the configured limit.
  bool foulLimitReached(TeamSide team) {
    final limit = format.foulLimit;
    return limit != null && tally(team).foulsIn(period) >= limit;
  }

  /// One foul away from the limit.
  bool foulLimitNear(TeamSide team) {
    final limit = format.foulLimit;
    return limit != null && tally(team).foulsIn(period) == limit - 1;
  }

  int get totalCards =>
      home.cards.values.fold<int>(0, (a, b) => a + b) +
      away.cards.values.fold<int>(0, (a, b) => a + b) +
      unassignedCards.values.fold<int>(0, (a, b) => a + b);

  int cardsOfColor(String color) =>
      home.cardsOf(color) + away.cardsOf(color) + (unassignedCards[color] ?? 0);

  /// Time elapsed in the current period at [now].
  Duration periodElapsedAt(DateTime now) {
    final since = runningSince;
    if (phase != MatchPhase.running || since == null) return elapsedAnchor;
    final delta = now.difference(since);
    return elapsedAnchor + (delta.isNegative ? Duration.zero : delta);
  }

  /// Cumulative match time at [now]: nominal duration of previous periods +
  /// elapsed time in the current one (so the 2nd half starts at 25:00 in 2×25).
  Duration matchTimeAt(DateTime now) {
    if (period <= 0) return Duration.zero;
    return format.startOf(period) + periodElapsedAt(now);
  }

  /// True if the current period has exceeded its nominal duration.
  bool isOvertimeAt(DateTime now) =>
      period > 0 && periodElapsedAt(now) > format.durationOf(period);

  /// Time spent on break so far.
  Duration? breakElapsedAt(DateTime now) {
    final b = breakStartedAt;
    if (phase != MatchPhase.onBreak || b == null) return null;
    final d = now.difference(b);
    return d.isNegative ? Duration.zero : d;
  }

  /// Remaining time of the active timeout (null if none).
  Duration? timeoutRemainingAt(DateTime now) {
    final t = activeTimeout;
    if (t == null) return null;
    final left = format.timeoutDuration - now.difference(t.startedAt);
    return left.isNegative ? Duration.zero : left;
  }

  /// Real duration of the match (wall clock).
  Duration? get realDuration {
    final s = matchStartedAt;
    final e = matchEndedAt;
    if (s == null || e == null) return null;
    return e.difference(s);
  }
}
