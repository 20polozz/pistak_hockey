import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/time_format.dart';
import '../../domain/match/match_event.dart';
import '../../domain/report/match_report.dart';

/// Localized texts for the PDF (built from AppLocalizations in the UI, so
/// this file stays free of Flutter and is unit-testable).
class ReportLabels {
  const ReportLabels({
    required this.title,
    required this.home,
    required this.away,
    required this.generalInfo,
    required this.statistics,
    required this.timeline,
    required this.incidents,
    required this.info,
    required this.stats,
    required this.eventLabel,
    required this.generatedWith,
    this.shootout,
  });

  final String title;
  final String home;
  final String away;
  final String generalInfo;
  final String statistics;
  final String timeline;
  final String incidents;

  /// (label, value) rows of general information.
  final List<(String, String)> info;

  /// (label, home, away) rows of statistics.
  final List<(String, String, String)> stats;
  final String Function(MatchEvent e) eventLabel;
  final String generatedWith;

  /// "(4–3 pen.)" when there was a shoot-out.
  final String? shootout;
}

/// Professional one-file match report. Uses the standard PDF fonts, so text
/// is sanitized to their character set (Latin-1: Catalan/Spanish accents OK).
class PdfReportExporter {
  const PdfReportExporter();

  static const _ink = PdfColor.fromInt(0xFF0B0F14);
  static const _accent = PdfColor.fromInt(0xFFB8F23A);
  static const _home = PdfColor.fromInt(0xFF3B8BFF);
  static const _away = PdfColor.fromInt(0xFFFF8A3D);
  static const _muted = PdfColor.fromInt(0xFF6B7280);
  static const _line = PdfColor.fromInt(0xFFE5E7EB);

  static String safe(String s) => s
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('’', "'")
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('…', '...')
      .replaceAll('×', 'x')
      .replaceAll('·', '-')
      .replaceAll(RegExp(r'[^\u0000-ÿ]'), '');

  Future<Uint8List> build(MatchReport report, ReportLabels l) async {
    final doc = pw.Document(title: safe(l.title), creator: 'PISTAK');
    final s = report.state;
    final bold = const pw.TextStyle(fontWeight: pw.FontWeight.bold);

    pw.Widget section(String title) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
          child: pw.Text(safe(title).toUpperCase(),
              style: const pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: _muted,
                  letterSpacing: 1)),
        );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 40),
      header: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _accent, width: 3))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('PISTAK',
                style: const pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 4,
                    color: _ink)),
            pw.Text(safe(l.title),
                style: const pw.TextStyle(fontSize: 10, color: _muted)),
          ],
        ),
      ),
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(safe(l.generatedWith),
              style: const pw.TextStyle(fontSize: 8, color: _muted)),
          pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: _muted)),
        ],
      ),
      build: (ctx) => [
        // Scoreboard
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 14),
          padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: pw.BoxDecoration(
              color: _ink, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Column(children: [
            pw.Row(children: [
              pw.Expanded(
                child: pw.Text(safe(l.home),
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(
                        color: _home,
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold)),
              ),
              pw.Text('${s.home.goals} - ${s.away.goals}',
                  style: const pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 32,
                      fontWeight: pw.FontWeight.bold)),
              pw.Expanded(
                child: pw.Text(safe(l.away),
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(
                        color: _away,
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold)),
              ),
            ]),
            if (l.shootout != null)
              pw.Text(safe(l.shootout!),
                  style: const pw.TextStyle(color: _accent, fontSize: 11)),
          ]),
        ),
        section(l.generalInfo),
        pw.TableHelper.fromTextArray(
          data: [
            for (final (k, v) in l.info) [safe(k), safe(v)]
          ],
          headerCount: 0,
          border: null,
          cellStyle: const pw.TextStyle(fontSize: 10),
          columnWidths: const {
            0: pw.FixedColumnWidth(140),
            1: pw.FlexColumnWidth(),
          },
          cellPadding:
              const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
          rowDecoration: const pw.BoxDecoration(
              border:
                  pw.Border(bottom: pw.BorderSide(color: _line, width: .5))),
        ),
        section(l.statistics),
        pw.TableHelper.fromTextArray(
          headers: [safe(l.home), '', safe(l.away)],
          data: [
            for (final (k, h, a) in l.stats) [h, safe(k), a]
          ],
          border: null,
          headerStyle: bold.copyWith(fontSize: 10),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellAlignment: pw.Alignment.center,
          headerAlignment: pw.Alignment.center,
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(2),
            2: pw.FlexColumnWidth(1),
          },
          rowDecoration: const pw.BoxDecoration(
              border:
                  pw.Border(bottom: pw.BorderSide(color: _line, width: .5))),
        ),
        if (report.lines.any((x) => x.event.type == EventTypes.incident)) ...[
          section(l.incidents),
          for (final x in report.lines)
            if (x.event.type == EventTypes.incident)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Text(
                    safe('${formatMatchTime(x.event.matchTime)}  '
                        '${x.event.text ?? l.eventLabel(x.event)}'),
                    style: const pw.TextStyle(fontSize: 10)),
              ),
        ],
        section(l.timeline),
        pw.TableHelper.fromTextArray(
          headers: const ['', '', '', '', ''],
          headerCount: 0,
          data: [
            for (final x in report.lines)
              [
                formatMatchTime(x.event.matchTime),
                formatClockTime(x.event.timestamp),
                safe([
                  l.eventLabel(x.event),
                  if (x.event.team == TeamSide.home) l.home,
                  if (x.event.team == TeamSide.away) l.away,
                  if (x.event.playerName != null) x.event.playerName!,
                ].join(' · ').replaceAll(' · ', ' - ')),
                x.event.type == EventTypes.goal
                    ? '${x.homeScore}-${x.awayScore}'
                    : '',
                safe(x.event.text ?? ''),
              ],
          ],
          border: null,
          cellStyle: const pw.TextStyle(fontSize: 9),
          oddRowDecoration:
              const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F6F8)),
          columnWidths: const {
            0: pw.FixedColumnWidth(42),
            1: pw.FixedColumnWidth(36),
            2: pw.FlexColumnWidth(3),
            3: pw.FixedColumnWidth(34),
            4: pw.FlexColumnWidth(3),
          },
          cellPadding:
              const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        ),
      ],
    ));
    return doc.save();
  }
}
