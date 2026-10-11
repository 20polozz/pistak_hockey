import '../sport/match_format.dart';
import 'match_event.dart';

/// Event times are shown like the big clock: time LEFT in the period
/// (25:00 → 0:00). They are stored as elapsed time (match/period time).
extension EventClock on MatchFormat {
  /// Clock shown for [e] (never negative; 0:00 once the time is up).
  Duration clockOf(MatchEvent e) => clockFor(e.period, e.periodTime);

  Duration clockFor(int period, Duration periodTime) {
    final left = durationOf(period < 1 ? 1 : period) - periodTime;
    return left.isNegative ? Duration.zero : left;
  }

  /// Inverse of [clockFor]: period time for a clock value of [period].
  Duration periodTimeForClock(int period, Duration clock) {
    final t = durationOf(period < 1 ? 1 : period) - clock;
    return t.isNegative ? Duration.zero : t;
  }
}
