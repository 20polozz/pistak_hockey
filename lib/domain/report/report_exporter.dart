import 'dart:convert';

import '../../core/time_format.dart';
import '../match/match_event.dart';
import 'match_report.dart';

/// Output format of a report. PDF (Phase 3) will implement the same
/// interface, returning bytes instead of text.
abstract class ReportExporter {
  String get id;
  String get fileExtension;
  String get mimeType;
  String export(MatchReport report);
}

/// Spreadsheet-friendly chronology (one row per event).
class CsvReportExporter implements ReportExporter {
  const CsvReportExporter();

  @override
  String get id => 'csv';
  @override
  String get fileExtension => 'csv';
  @override
  String get mimeType => 'text/csv';

  static const header = [
    'match_time',
    'period',
    'type',
    'subtype',
    'team',
    'score_home',
    'score_away',
    'timestamp_utc',
    'text',
    'event_id',
  ];

  @override
  String export(MatchReport report) {
    final b = StringBuffer()..writeln(header.join(','));
    for (final l in report.lines) {
      final e = l.event;
      b.writeln([
        formatMatchTime(e.matchTime),
        '${e.period}',
        e.type,
        e.subtype ?? '',
        e.team?.code ?? '',
        '${l.homeScore}',
        '${l.awayScore}',
        e.timestamp.toUtc().toIso8601String(),
        e.text ?? '',
        e.id,
      ].map(_cell).join(','));
    }
    return b.toString();
  }

  static String _cell(String v) {
    final needsQuotes =
        v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r');
    final escaped = v.replaceAll('"', '""');
    return needsQuotes ? '"$escaped"' : escaped;
  }
}

/// Full machine-readable export (match + stats + events).
class JsonReportExporter implements ReportExporter {
  const JsonReportExporter();

  @override
  String get id => 'json';
  @override
  String get fileExtension => 'json';
  @override
  String get mimeType => 'application/json';

  @override
  String export(MatchReport report) {
    final s = report.state;
    Map<String, dynamic> team(TeamSide side) {
      final t = s.tally(side);
      return {
        'goals': t.goals,
        'fouls': t.fouls,
        'timeouts': t.timeouts,
        'cards': t.cards,
      };
    }

    return const JsonEncoder.withIndent('  ').convert({
      'format': 'pistak.match.v1',
      'match': report.info.toJson(),
      'stats': {
        'home': team(TeamSide.home),
        'away': team(TeamSide.away),
        'unassignedCards': s.unassignedCards,
        'incidents': s.incidents,
        'pauses': s.pauses,
        'startedAt': s.matchStartedAt?.toIso8601String(),
        'endedAt': s.matchEndedAt?.toIso8601String(),
      },
      'events': [for (final l in report.lines) l.event.toJson()],
    });
  }
}

const reportExporters = <ReportExporter>[
  CsvReportExporter(),
  JsonReportExporter(),
];
