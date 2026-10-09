import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/match/match_event.dart';
import '../../domain/match/match_state.dart';
import '../../domain/report/match_report.dart';
import '../../domain/report/report_exporter.dart';
import '../../l10n/app_localizations.dart';
import '../../services/export/file_sharer.dart';
import '../../services/export/pdf_report.dart';
import '../providers.dart';
import '../widgets/event_labels.dart';
import 'match_details_screen.dart';
import 'timeline_screen.dart';

/// Basic report view (Phase 1). PDF/CSV/JSON export arrive in Phase 3 and
/// will be generated from this same data (MatchView).
class MatchSummaryScreen extends ConsumerWidget {
  const MatchSummaryScreen({super.key, required this.matchId});
  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final view = ref.watch(matchViewProvider(matchId));
    return Scaffold(
      appBar: AppBar(
        title: Text(l.summary),
        actions: [
          if (view.valueOrNull != null)
            PopupMenuButton<String>(
              tooltip: l.exportAction,
              icon: const Icon(Icons.ios_share),
              onSelected: (format) =>
                  _export(context, l, view.valueOrNull!, format),
              itemBuilder: (_) => [
                for (final f in const ['pdf', 'csv', 'json'])
                  PopupMenuItem(
                      value: f,
                      child: Text('${l.exportAction} ${f.toUpperCase()}')),
                PopupMenuItem(value: 'copy-csv', child: Text(l.copyCsv)),
              ],
            ),
          IconButton(
            tooltip: l.edit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => MatchDetailsScreen(matchId: matchId))),
          ),
        ],
      ),
      body: view.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (v) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _header(l, v),
                const SizedBox(height: 16),
                _section(context, l.generalInfo, _general(l, v)),
                const SizedBox(height: 16),
                _section(context, l.statistics, _stats(l, v)),
                if (_incidents(v).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _section(
                    context,
                    l.incidentsSection,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final e in _incidents(v))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                                '${formatMatchTime(e.matchTime)} · ${e.text ?? eventLabel(l, e)}'),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _section(
                  context,
                  l.timeline,
                  Column(
                    children: [
                      for (final t in buildTimelineTiles(context, v))
                        Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: t),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context, AppLocalizations l, MatchView v,
      String format) async {
    final report = MatchReport.build(v.info, v.events);
    final title = matchTitle(l, v.info);
    final date = v.info.displayDate;
    if (format == 'copy-csv') {
      await Clipboard.setData(
          ClipboardData(text: const CsvReportExporter().export(report)));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.exportCopied('CSV'))));
      }
      return;
    }
    final Uint8List bytes;
    final String mime;
    if (format == 'pdf') {
      bytes = await const PdfReportExporter()
          .build(report, _pdfLabels(l, v, title));
      mime = 'application/pdf';
    } else {
      final ex = reportExporters.firstWhere((e) => e.id == format);
      bytes = Uint8List.fromList(utf8.encode(ex.export(report)));
      mime = ex.mimeType;
    }
    try {
      await const FileSharer().share(bytes,
          fileName: reportFileName(title, date, format), mimeType: mime);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  ReportLabels _pdfLabels(AppLocalizations l, MatchView v, String title) {
    final s = v.state;
    int cards(TeamSide t, String c) => s.tally(t).cardsOf(c);
    return ReportLabels(
      title: title,
      home: teamName(l, v.info, TeamSide.home),
      away: teamName(l, v.info, TeamSide.away),
      generalInfo: l.generalInfo,
      statistics: l.statistics,
      timeline: l.timeline,
      incidents: l.incidentsSection,
      info: [
        for (final (k, val) in _generalRows(l, v))
          if (val != null) (k, val),
      ],
      stats: [
        (l.statGoals, '${s.home.goals}', '${s.away.goals}'),
        (l.statFouls, '${s.home.fouls}', '${s.away.fouls}'),
        (
          l.statYellow,
          '${cards(TeamSide.home, CardColors.yellow)}',
          '${cards(TeamSide.away, CardColors.yellow)}'
        ),
        (
          l.statBlue,
          '${cards(TeamSide.home, CardColors.blue)}',
          '${cards(TeamSide.away, CardColors.blue)}'
        ),
        (
          l.statRed,
          '${cards(TeamSide.home, CardColors.red)}',
          '${cards(TeamSide.away, CardColors.red)}'
        ),
        (l.statTimeouts, '${s.home.timeouts}', '${s.away.timeouts}'),
        if (s.home.saves + s.away.saves > 0)
          (l.statSaves, '${s.home.saves}', '${s.away.saves}'),
        if (s.hadShootout)
          (
            l.statShootout,
            '${s.home.shootoutScored}',
            '${s.away.shootoutScored}'
          ),
        (l.statIncidents, '${s.incidents}', ''),
        (l.statPauses, '${s.pauses}', ''),
      ],
      eventLabel: (e) => eventLabel(l, e),
      generatedWith: 'PISTAK · ${l.tagline}',
      shootout: s.hadShootout
          ? l.shootoutScore(s.home.shootoutScored, s.away.shootoutScored)
          : null,
    );
  }

  List<MatchEvent> _incidents(MatchView v) =>
      v.activeEvents.where((e) => e.type == EventTypes.incident).toList();

  Widget _header(AppLocalizations l, MatchView v) {
    final s = v.state;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PistakColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(teamName(l, v.info, TeamSide.home),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: PistakColors.home,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
          ),
          // Already huge: grows at most 1.2× with the system text size.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: Text('${s.home.goals} – ${s.away.goals}',
                style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    fontFeatures: tabularFigures)),
          ),
          Expanded(
            child: Text(teamName(l, v.info, TeamSide.away),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: PistakColors.away,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, Widget child) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );

  List<(String, String?)> _generalRows(AppLocalizations l, MatchView v) {
    final i = v.info;
    final s = v.state;
    return <(String, String?)>[
      (l.fieldCategory, i.category),
      (l.fieldCompetition, i.competition),
      (l.fieldSeason, i.season),
      (l.fieldVenue, i.venue),
      (l.date, formatDate(i.displayDate)),
      (
        l.startTime,
        s.matchStartedAt == null ? null : formatClockTime(s.matchStartedAt!)
      ),
      (
        l.endTime,
        s.matchEndedAt == null ? null : formatClockTime(s.matchEndedAt!)
      ),
      (
        l.duration,
        s.realDuration == null ? null : formatMatchTime(s.realDuration!)
      ),
      (l.fieldFormat, i.format.name),
      (l.fieldNotes, i.notes),
    ];
  }

  Widget _general(AppLocalizations l, MatchView v) {
    final rows = _generalRows(l, v);
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 140,
                  child: Text(r.$1,
                      style: const TextStyle(color: PistakColors.textMuted)),
                ),
                Expanded(child: Text(r.$2 ?? '—')),
              ],
            ),
          ),
      ],
    );
  }

  Widget _stats(AppLocalizations l, MatchView v) {
    final s = v.state;
    TableRow row(String label, Object home, Object away, {bool bold = false}) {
      final style = TextStyle(
          fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
          fontFeatures: tabularFigures);
      return TableRow(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text('$home', textAlign: TextAlign.center, style: style),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(label, textAlign: TextAlign.center),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text('$away', textAlign: TextAlign.center, style: style),
        ),
      ]);
    }

    int cards(MatchState st, TeamSide side, String color) =>
        st.tally(side).cardsOf(color);

    final unassigned = s.unassignedCards.values.fold<int>(0, (a, b) => a + b);
    return Column(
      children: [
        Table(
          columnWidths: const {
            0: FlexColumnWidth(1),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(1),
          },
          children: [
            TableRow(children: [
              Text(l.homeUpper,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: PistakColors.home, fontWeight: FontWeight.w800)),
              const SizedBox.shrink(),
              Text(l.awayUpper,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: PistakColors.away, fontWeight: FontWeight.w800)),
            ]),
            row(l.statGoals, s.home.goals, s.away.goals, bold: true),
            row(l.statFouls, s.home.fouls, s.away.fouls),
            row(l.statYellow, cards(s, TeamSide.home, CardColors.yellow),
                cards(s, TeamSide.away, CardColors.yellow)),
            row(l.statBlue, cards(s, TeamSide.home, CardColors.blue),
                cards(s, TeamSide.away, CardColors.blue)),
            row(l.statRed, cards(s, TeamSide.home, CardColors.red),
                cards(s, TeamSide.away, CardColors.red)),
            row(l.statTimeouts, s.home.timeouts, s.away.timeouts),
            if (s.home.saves + s.away.saves > 0)
              row(l.statSaves, s.home.saves, s.away.saves),
            if (s.home.penaltyAttempts + s.away.penaltyAttempts > 0)
              row(
                  l.statPenalties,
                  '${s.home.penaltyScored}/${s.home.penaltyAttempts}',
                  '${s.away.penaltyScored}/${s.away.penaltyAttempts}'),
            if (s.home.freeHitAttempts + s.away.freeHitAttempts > 0)
              row(
                  l.statFreeHits,
                  '${s.home.freeHitScored}/${s.home.freeHitAttempts}',
                  '${s.away.freeHitScored}/${s.away.freeHitAttempts}'),
            if (s.hadShootout)
              row(l.statShootout, s.home.shootoutScored, s.away.shootoutScored,
                  bold: true),
          ],
        ),
        const Divider(height: 24),
        _kv(l.statIncidents, '${s.incidents}'),
        _kv(l.statPauses, '${s.pauses}'),
        if (unassigned > 0) _kv(l.statUnassignedCards, '$unassigned'),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
              child: Text(k,
                  style: const TextStyle(color: PistakColors.textMuted))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}
