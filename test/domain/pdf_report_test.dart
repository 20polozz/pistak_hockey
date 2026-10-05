import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/core/clock.dart';
import 'package:pistak/core/ids.dart';
import 'package:pistak/domain/match/event_factory.dart';
import 'package:pistak/domain/match/match_event.dart';
import 'package:pistak/domain/match/match_info.dart';
import 'package:pistak/domain/match/match_projector.dart';
import 'package:pistak/domain/match/match_state.dart';
import 'package:pistak/domain/report/match_report.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';
import 'package:pistak/services/export/file_sharer.dart';
import 'package:pistak/services/export/pdf_report.dart';

void main() {
  test('PDF report renders a complete match (accents, many events)', () async {
    final clock = FakeClock(DateTime.utc(2026, 10, 12, 16, 30));
    final f = EventFactory(
        matchId: 'm',
        deviceId: 'd',
        clock: clock,
        ids: SequentialIdGenerator());
    final events = <MatchEvent>[];
    final info = MatchInfo(
      id: 'm',
      sport: rollerHockey.id,
      format: rollerHockey.defaultFormat,
      homeName: 'CP Vic',
      awayName: 'Reus Deportiu',
      competition: 'OK Lliga',
      category: 'Sènior',
      venue: 'Pavelló Olímpic',
      createdAt: clock.now(),
      updatedAt: clock.now(),
      deviceId: 'd',
    );
    void run(List<MatchEvent> Function(MatchState s) c) {
      final s = const MatchProjector().project(info.format, events);
      events.addAll(c(s));
      clock.advance(const Duration(seconds: 47));
    }

    run((s) => f.startMatch(s));
    for (var i = 0; i < 40; i++) {
      run((s) => switch (i % 5) {
            0 => f.goal(s, TeamSide.home),
            1 => f.foul(s, TeamSide.away),
            2 => f.card(s, CardColors.blue, team: TeamSide.home),
            3 => f.incident(s,
                kind: IncidentKinds.text,
                text: 'Aturada per la pista mullada – àrea “nord”'),
            _ => f.goal(s, TeamSide.away),
          });
    }
    run((s) => f.endMatch(s));

    final report = MatchReport.build(info, events);
    final bytes = await const PdfReportExporter().build(
      report,
      ReportLabels(
        title: 'CP Vic – Reus Deportiu',
        home: 'CP Vic',
        away: 'Reus Deportiu',
        generalInfo: 'Informació general',
        statistics: 'Estadístiques',
        timeline: 'Cronologia',
        incidents: 'Incidències',
        info: const [
          ('Competició', 'OK Lliga'),
          ('Pavelló', 'Pavelló Olímpic')
        ],
        stats: [
          ('Gols', '${report.state.home.goals}', '${report.state.away.goals}')
        ],
        eventLabel: (e) => e.type,
        generatedWith: 'PISTAK · Matchday made simple.',
      ),
    );
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(3000));
    // Kept for visual inspection during development.
    final out = File('build/test_report.pdf')..createSync(recursive: true);
    out.writeAsBytesSync(bytes);
  });

  test('safe() keeps Catalan/Spanish letters and drops the rest', () {
    expect(PdfReportExporter.safe('Pavelló · Ñ – “x” 2×25 ⚽'),
        'Pavelló - Ñ - "x" 2x25 ');
  });

  test('report file names are safe', () {
    expect(reportFileName('CP A / HC: B', DateTime(2026, 10, 12), 'pdf'),
        'pistak_CP_A_HC_B_2026-10-12.pdf');
  });
}
