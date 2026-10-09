import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/match/match_event.dart';
import '../../domain/match/match_projector.dart';
import '../../domain/stats/team_stats.dart';
import '../../domain/team/team.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../widgets/event_labels.dart';

/// Every match projected, recomputed whenever matches change.
final playedMatchesProvider =
    FutureProvider.autoDispose<List<PlayedMatch>>((ref) async {
  final infos = await ref.watch(matchesProvider.future);
  final repo = ref.watch(matchRepositoryProvider);
  const projector = MatchProjector();
  return [
    for (final info in infos)
      await repo.getEvents(info.id).then(
          (ev) => PlayedMatch(info, projector.project(info.format, ev), ev)),
  ];
});

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  String? _teamId;
  String? _season; // null = all

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final teams = ref.watch(teamsProvider).valueOrNull ?? const <Team>[];
    final played = ref.watch(playedMatchesProvider);
    final teamId = teams.any((t) => t.id == _teamId)
        ? _teamId
        : (teams.isEmpty ? null : teams.first.id);

    return Scaffold(
      appBar: AppBar(title: Text(l.statistics)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: teams.isEmpty
              ? _empty(l.statsNoTeams)
              : played.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                  data: (all) => _body(l, teams, teamId!, all),
                ),
        ),
      ),
    );
  }

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: PistakColors.textMuted)),
        ),
      );

  Widget _body(AppLocalizations l, List<Team> teams, String teamId,
      List<PlayedMatch> all) {
    final mine = all
        .where(
            (m) => m.info.homeTeamId == teamId || m.info.awayTeamId == teamId)
        .toList();
    final seasons = {
      for (final m in mine)
        if (m.info.season?.trim().isNotEmpty ?? false) m.info.season!
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    final season = seasons.contains(_season) ? _season : null;
    final t = TeamStats.compute(all, teamId, season: season);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: teamId,
          decoration: InputDecoration(labelText: l.team),
          items: [
            for (final team in teams)
              DropdownMenuItem(value: team.id, child: Text(team.name)),
          ],
          onChanged: (id) => setState(() {
            _teamId = id;
            _season = null;
          }),
        ),
        if (seasons.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              label: Text(l.allSeasons),
              selected: season == null,
              onSelected: (_) => setState(() => _season = null),
            ),
            for (final s in seasons)
              ChoiceChip(
                label: Text(s),
                selected: season == s,
                onSelected: (_) => setState(() => _season = s),
              ),
          ]),
        ],
        const SizedBox(height: 16),
        if (mine.isEmpty)
          _empty(l.statsNoMatches)
        else ...[
          _recordCard(l, t),
          const SizedBox(height: 16),
          _playersCard(l, t),
        ],
      ],
    );
  }

  Widget _recordCard(AppLocalizations l, TeamStats t) {
    Widget cell(String label, String value, {Color? color}) => Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    fontFeatures: tabularFigures,
                    color: color)),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, color: PistakColors.textMuted)),
          ],
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            Expanded(child: cell(l.statsPlayed, '${t.played}')),
            Expanded(
                child:
                    cell(l.statsWins, '${t.wins}', color: PistakColors.synced)),
            Expanded(child: cell(l.statsDraws, '${t.draws}')),
            Expanded(
                child: cell(l.statsLosses, '${t.losses}',
                    color: PistakColors.danger)),
          ]),
          const Divider(height: 28),
          Row(children: [
            Expanded(child: cell(l.statsGoalsFor, '${t.goalsFor}')),
            Expanded(child: cell(l.statsGoalsAgainst, '${t.goalsAgainst}')),
            Expanded(
                child: cell(l.statsPoints, '${t.points}',
                    color: PistakColors.accent)),
          ]),
          const Divider(height: 28),
          Row(children: [
            Expanded(
                child: cell(l.statYellow, '${t.yellow}',
                    color: cardColor(CardColors.yellow))),
            Expanded(
                child: cell(l.statBlue, '${t.blue}',
                    color: cardColor(CardColors.blue))),
            Expanded(
                child: cell(l.statRed, '${t.red}',
                    color: cardColor(CardColors.red))),
          ]),
          if (t.penaltiesTaken + t.freeHitsTaken > 0) ...[
            const Divider(height: 28),
            Row(children: [
              Expanded(
                  child: cell(l.statPenalties,
                      '${t.penaltiesScored}/${t.penaltiesTaken}')),
              Expanded(
                  child: cell(l.statFreeHits,
                      '${t.freeHitsScored}/${t.freeHitsTaken}')),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _playersCard(AppLocalizations l, TeamStats t) {
    final rows = t.ranking;
    Widget head(String s) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(s,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: PistakColors.textMuted)),
        );
    Widget num(int v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('$v',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFeatures: tabularFigures,
                  fontWeight: bold ? FontWeight.w900 : FontWeight.w500)),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.statsPlayers,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              Text(l.statsNoPlayers,
                  style: const TextStyle(color: PistakColors.textMuted))
            else
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(4),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1),
                  3: FlexColumnWidth(1),
                  4: FlexColumnWidth(2),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(children: [
                    const SizedBox.shrink(),
                    Semantics(
                        label: l.statGoals, child: head(l.statsGoalsShort)),
                    Semantics(
                        label: l.assist, child: head(l.statsAssistsShort)),
                    Semantics(
                        label: l.statSaves, child: head(l.statsSavesShort)),
                    head(l.statsCards),
                  ]),
                  for (final p in rows)
                    TableRow(children: [
                      Text(p.label,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      num(p.goals, bold: true),
                      num(p.assists),
                      num(p.saves),
                      _cardDots(p),
                    ]),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _cardDots(PlayerStats p) => Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        children: [
          for (final (color, n) in [
            (CardColors.yellow, p.yellow),
            (CardColors.blue, p.blue),
            (CardColors.red, p.red),
          ])
            if (n > 0)
              Text('■ $n',
                  style: TextStyle(
                      color: cardColor(color), fontWeight: FontWeight.w800)),
        ],
      );
}
