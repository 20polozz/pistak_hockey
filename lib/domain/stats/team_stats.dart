import '../match/match_event.dart';
import '../match/match_info.dart';
import '../match/match_state.dart';

/// One match already projected (input of the statistics).
class PlayedMatch {
  const PlayedMatch(this.info, this.state, this.events);
  final MatchInfo info;
  final MatchState state;
  final List<MatchEvent> events;
}

enum MatchResult { win, draw, loss }

class PlayerStats {
  PlayerStats(this.playerId, this.label);
  final String playerId;
  String label;
  int goals = 0;
  int assists = 0;
  int yellow = 0;
  int blue = 0;
  int red = 0;
  int saves = 0;
  int get cards => yellow + blue + red;
}

/// Season record of one of the user's teams (matches linked to it).
class TeamStats {
  int played = 0;
  int wins = 0;
  int draws = 0;
  int losses = 0;
  int goalsFor = 0;
  int goalsAgainst = 0;
  int yellow = 0;
  int blue = 0;
  int red = 0;
  int penaltiesScored = 0;
  int penaltiesTaken = 0;
  int freeHitsScored = 0;
  int freeHitsTaken = 0;
  int saves = 0;
  final Map<String, PlayerStats> players = {};

  int get goalDifference => goalsFor - goalsAgainst;
  int get points => wins * 3 + draws; // roller hockey leagues: 3/1/0

  /// Top scorers first, then assists, then name.
  List<PlayerStats> get ranking => players.values.toList()
    ..sort((a, b) {
      final g = b.goals.compareTo(a.goals);
      if (g != 0) return g;
      final s = b.assists.compareTo(a.assists);
      if (s != 0) return s;
      return a.label.compareTo(b.label);
    });

  /// Statistics of [teamId] over [matches] (only FINISHED matches count for
  /// the record; player numbers count from every match). [season] null = all.
  static TeamStats compute(Iterable<PlayedMatch> matches, String teamId,
      {String? season}) {
    final t = TeamStats();
    for (final m in matches) {
      final info = m.info;
      if (info.deletedAt != null) continue;
      if (season != null && info.season != season) continue;
      final TeamSide side;
      if (info.homeTeamId == teamId) {
        side = TeamSide.home;
      } else if (info.awayTeamId == teamId) {
        side = TeamSide.away;
      } else {
        continue;
      }
      final other = side == TeamSide.home ? TeamSide.away : TeamSide.home;
      final s = m.state;
      final mine = s.tally(side);
      if (s.isFinished) {
        t.played++;
        t.goalsFor += mine.goals;
        t.goalsAgainst += s.tally(other).goals;
        switch (resultFor(s, side)) {
          case MatchResult.win:
            t.wins++;
          case MatchResult.draw:
            t.draws++;
          case MatchResult.loss:
            t.losses++;
        }
      }
      t.yellow += mine.cardsOf(CardColors.yellow);
      t.blue += mine.cardsOf(CardColors.blue);
      t.red += mine.cardsOf(CardColors.red);
      t.penaltiesScored += mine.penaltyScored;
      t.penaltiesTaken += mine.penaltyAttempts;
      t.freeHitsScored += mine.freeHitScored;
      t.freeHitsTaken += mine.freeHitAttempts;
      t.saves += mine.saves;

      for (final e in m.events) {
        if (e.isVoided || e.team != side) continue;
        final pid = e.metadata[MetaKeys.playerId] as String?;
        if (pid != null && pid.isNotEmpty) {
          final p = t.players
              .putIfAbsent(pid, () => PlayerStats(pid, e.playerName ?? '?'));
          if (e.playerName != null) p.label = e.playerName!;
          switch (e.type) {
            case EventTypes.goal:
              p.goals++;
            case EventTypes.save:
              p.saves++;
            case EventTypes.card:
              switch (e.subtype) {
                case CardColors.yellow:
                  p.yellow++;
                case CardColors.blue:
                  p.blue++;
                case CardColors.red:
                  p.red++;
              }
          }
        }
        final aid = e.metadata[MetaKeys.assistId] as String?;
        if (e.type == EventTypes.goal && aid != null && aid.isNotEmpty) {
          t.players
              .putIfAbsent(aid, () => PlayerStats(aid, e.assistName ?? '?'))
              .assists++;
        }
      }
    }
    return t;
  }

  /// Regular/overtime goals decide; a tie settled by penalties (shoot-out)
  /// counts as a win for the shoot-out winner.
  static MatchResult resultFor(MatchState s, TeamSide side) {
    final other = side == TeamSide.home ? TeamSide.away : TeamSide.home;
    var a = s.tally(side).goals, b = s.tally(other).goals;
    if (a == b && s.hadShootout) {
      a = s.tally(side).shootoutScored;
      b = s.tally(other).shootoutScored;
    }
    return a > b
        ? MatchResult.win
        : a == b
            ? MatchResult.draw
            : MatchResult.loss;
  }
}
