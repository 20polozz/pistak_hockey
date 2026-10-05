import '../match/match_event.dart';
import '../match/match_info.dart';
import '../match/match_projector.dart';
import '../match/match_state.dart';

/// One row of the chronological report.
class ReportLine {
  const ReportLine({
    required this.event,
    required this.homeScore,
    required this.awayScore,
  });

  final MatchEvent event;

  /// Score right after this event.
  final int homeScore;
  final int awayScore;
}

/// Everything an exporter needs, independent of UI and output format.
class MatchReport {
  MatchReport._(this.info, this.state, this.lines);

  factory MatchReport.build(MatchInfo info, Iterable<MatchEvent> events) {
    final active = events.where((e) => !e.isVoided).toList()
      ..sort(compareEvents);
    var home = 0;
    var away = 0;
    final lines = <ReportLine>[];
    for (final e in active) {
      if (e.type == EventTypes.goal) {
        if (e.team == TeamSide.home) home++;
        if (e.team == TeamSide.away) away++;
      }
      lines.add(ReportLine(event: e, homeScore: home, awayScore: away));
    }
    return MatchReport._(
        info, const MatchProjector().project(info.format, active), lines);
  }

  final MatchInfo info;
  final MatchState state;
  final List<ReportLine> lines;
}
