import '../team/team.dart';
import 'match_info.dart';

enum ResultFilter { win, draw, loss }

/// History filters: team, competition, category, date range and result
/// (result is relative to the selected team).
class MatchFilter {
  const MatchFilter({
    this.team,
    this.competition,
    this.category,
    this.from,
    this.to,
    this.result,
  });

  final Team? team;
  final String? competition;
  final String? category;
  final DateTime? from;
  final DateTime? to;
  final ResultFilter? result;

  bool get isEmpty =>
      team == null &&
      competition == null &&
      category == null &&
      from == null &&
      to == null &&
      result == null;

  MatchFilter copyWith({
    Team? team,
    bool clearTeam = false,
    String? competition,
    bool clearCompetition = false,
    String? category,
    bool clearCategory = false,
    DateTime? from,
    DateTime? to,
    bool clearDates = false,
    ResultFilter? result,
    bool clearResult = false,
  }) =>
      MatchFilter(
        team: clearTeam ? null : (team ?? this.team),
        competition:
            clearCompetition ? null : (competition ?? this.competition),
        category: clearCategory ? null : (category ?? this.category),
        from: clearDates ? null : (from ?? this.from),
        to: clearDates ? null : (to ?? this.to),
        result: clearResult ? null : (result ?? this.result),
      );

  /// Which side [team] played in [m] (by link, else by exact name).
  static bool? isHome(MatchInfo m, Team team) {
    if (m.homeTeamId == team.id) return true;
    if (m.awayTeamId == team.id) return false;
    final n = team.name.trim().toLowerCase();
    if ((m.homeName ?? '').trim().toLowerCase() == n) return true;
    if ((m.awayName ?? '').trim().toLowerCase() == n) return false;
    return null;
  }

  bool matches(MatchInfo m) {
    final t = team;
    bool? home;
    if (t != null) {
      home = isHome(m, t);
      if (home == null) return false;
    }
    if (competition != null && m.competition != competition) return false;
    if (category != null && m.category != category) return false;
    final d = m.displayDate.toLocal();
    final f = from;
    if (f != null && d.isBefore(DateTime(f.year, f.month, f.day))) return false;
    final tt = to;
    if (tt != null && !d.isBefore(DateTime(tt.year, tt.month, tt.day + 1))) {
      return false;
    }
    final r = result;
    if (r != null) {
      if (home == null || m.status != MatchStatus.finished) return false;
      final mine = home ? m.homeScore : m.awayScore;
      final theirs = home ? m.awayScore : m.homeScore;
      final actual = mine > theirs
          ? ResultFilter.win
          : mine == theirs
              ? ResultFilter.draw
              : ResultFilter.loss;
      if (actual != r) return false;
    }
    return true;
  }

  List<MatchInfo> apply(List<MatchInfo> list) =>
      isEmpty ? list : list.where(matches).toList();
}

/// The earliest scheduled match that hasn't started and is today or later.
MatchInfo? nextScheduledMatch(List<MatchInfo> list, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  MatchInfo? best;
  for (final m in list) {
    final s = m.scheduledAt;
    if (s == null || m.status != MatchStatus.notStarted) continue;
    if (s.toLocal().isBefore(today)) continue;
    if (best == null || s.isBefore(best.scheduledAt!)) best = m;
  }
  return best;
}
