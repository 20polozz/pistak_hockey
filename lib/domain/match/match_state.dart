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

  int get fouls => foulsByPeriod.values.fold(0, (a, b) => a + b);
  int get timeouts => timeoutsByPeriod.values.fold(0, (a, b) => a + b);
  int foulsIn(int period) => foulsByPeriod[period] ?? 0;
  int timeoutsIn(int period) => timeoutsByPeriod[period] ?? 0;
  int cardsOf(String color) => cards[color] ?? 0;
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
  bool get isLastPeriod => period >= format.periods;

  int get totalCards =>
      home.cards.values.fold(0, (a, b) => a + b) +
      away.cards.values.fold(0, (a, b) => a + b) +
      unassignedCards.values.fold(0, (a, b) => a + b);

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
    return format.periodDuration * (period - 1) + periodElapsedAt(now);
  }

  /// True if the current period has exceeded its nominal duration.
  bool isOvertimeAt(DateTime now) =>
      period > 0 && periodElapsedAt(now) > format.periodDuration;

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
