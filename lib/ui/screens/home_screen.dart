import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/match/match_filter.dart';
import '../../domain/match/match_info.dart';
import '../../domain/sport/sports.dart';
import '../../domain/team/team.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../widgets/brand.dart';
import '../widgets/storage_banner.dart';
import '../widgets/event_labels.dart';
import '../widgets/sync_badge.dart';
import 'match_details_screen.dart';
import 'match_screen.dart';
import 'match_summary_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'teams_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final active = ref.watch(activeMatchProvider).valueOrNull;
    final matches = ref.watch(matchesProvider);
    final filter = ref.watch(matchFilterProvider);
    final all = matches.valueOrNull ?? const <MatchInfo>[];
    final next = nextScheduledMatch(all, DateTime.now());

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // Transparent over the sport image; solid once the list scrolls.
        backgroundColor: WidgetStateColor.resolveWith((s) =>
            s.contains(WidgetState.scrolledUnder)
                ? PistakColors.background
                : Colors.transparent),
        actions: [
          if (isBackendConfigured) const SyncBadge(),
          IconButton(
            tooltip: l.statistics,
            icon: const Icon(Icons.bar_chart),
            onPressed: () => _push(context, const StatsScreen()),
          ),
          IconButton(
            tooltip: l.settings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _push(context, const SettingsScreen()),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          SportHeader(sportName: l.sportName),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const StorageBanner(),
                    if (active != null) ...[
                      _ActiveMatchCard(match: active),
                      const SizedBox(height: 16),
                    ],
                    if (next != null && next.id != active?.id) ...[
                      _NextMatchCard(match: next),
                      const SizedBox(height: 16),
                    ],
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(72)),
                      icon: const Icon(Icons.add_circle_outline, size: 28),
                      label: Text(l.newMatch,
                          style: const TextStyle(fontSize: 20)),
                      onPressed: () => _newMatch(context, ref),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.groups_outlined),
                          label: Text(l.myTeams),
                          onPressed: () => _push(context, const TeamsScreen()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.event_outlined),
                          label: Text(l.scheduleMatch),
                          onPressed: () => _schedule(context, ref),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 28),
                    Row(children: [
                      Expanded(
                        child: Text(l.myMatches,
                            style: Theme.of(context).textTheme.titleLarge),
                      ),
                      Badge(
                        isLabelVisible: !filter.isEmpty,
                        backgroundColor: PistakColors.accent,
                        child: IconButton(
                          tooltip: l.filters,
                          icon: const Icon(Icons.filter_list),
                          onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            showDragHandle: true,
                            builder: (_) => FilterSheet(matches: all),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    ...matches.when<List<Widget>>(
                      loading: () => [const LinearProgressIndicator()],
                      error: (e, _) => [Text('$e')],
                      data: (list) => _grouped(context, l, filter, list),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _grouped(BuildContext context, AppLocalizations l,
      MatchFilter filter, List<MatchInfo> list) {
    if (list.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(l.noMatchesYet,
              textAlign: TextAlign.center,
              style: const TextStyle(color: PistakColors.textMuted)),
        ),
      ];
    }
    final shown = filter.apply(list)
      ..sort((a, b) => b.displayDate.compareTo(a.displayDate));
    if (shown.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(l.noResults, textAlign: TextAlign.center),
        ),
      ];
    }
    final month = DateFormat.yMMMM(l.localeName);
    final out = <Widget>[];
    String? current;
    for (final m in shown) {
      final header = month.format(m.displayDate.toLocal());
      if (header != current) {
        current = header;
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Text(
            header[0].toUpperCase() + header.substring(1),
            style: const TextStyle(
                color: PistakColors.textMuted, fontWeight: FontWeight.w700),
          ),
        ));
      }
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _MatchTile(match: m),
      ));
    }
    return out;
  }

  static void _push(BuildContext context, Widget screen) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));

  /// NEW MATCH: creates an untitled match instantly (no form to fill) and
  /// opens the recording screen. Details can be completed later.
  Future<void> _newMatch(BuildContext context, WidgetRef ref) async {
    final sport = Sports.defaultSport;
    final format = await ref.read(settingsRepositoryProvider).lastFormat() ??
        sport.defaultFormat;
    final match = await ref
        .read(matchRepositoryProvider)
        .createMatch(sport: sport.id, format: format);
    if (!context.mounted) return;
    _push(context, MatchScreen(matchId: match.id));
  }

  /// Schedule: a not-started match with a date, completed in the details form.
  Future<void> _schedule(BuildContext context, WidgetRef ref) async {
    final sport = Sports.defaultSport;
    final format = await ref.read(settingsRepositoryProvider).lastFormat() ??
        sport.defaultFormat;
    final now = DateTime.now();
    final when = DateTime(now.year, now.month, now.day + 1, 18);
    final match = await ref.read(matchRepositoryProvider).createMatch(
        sport: sport.id, format: format, scheduledAt: when.toUtc());
    if (!context.mounted) return;
    _push(context,
        MatchDetailsScreen(matchId: match.id, discardIfNotSaved: true));
  }
}

class _ActiveMatchCard extends StatelessWidget {
  const _ActiveMatchCard({required this.match});
  final MatchInfo match;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _HighlightCard(
      color: PistakColors.accent,
      header: l.matchInProgress.toUpperCase(),
      dotColor: PistakColors.danger,
      title: matchTitle(l, match),
      big: '${match.homeScore} – ${match.awayScore}',
      button: l.continueMatch,
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MatchScreen(matchId: match.id))),
    );
  }
}

class _NextMatchCard extends StatelessWidget {
  const _NextMatchCard({required this.match});
  final MatchInfo match;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final at = match.scheduledAt!;
    return _HighlightCard(
      color: PistakColors.home,
      header: l.nextMatch.toUpperCase(),
      title: matchTitle(l, match),
      big: '${formatDate(at)}  ${formatClockTime(at)}',
      sub: match.venue,
      button: l.startScheduledMatch,
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MatchScreen(matchId: match.id))),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.color,
    required this.header,
    required this.title,
    required this.big,
    required this.button,
    required this.onPressed,
    this.sub,
    this.dotColor,
  });

  final Color color;
  final String header;
  final String title;
  final String big;
  final String? sub;
  final String button;
  final Color? dotColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            if (dotColor != null) ...[
              Icon(Icons.fiber_manual_record, color: dotColor, size: 14),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(header,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, letterSpacing: 1.2)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text(big,
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  fontFeatures: tabularFigures)),
          if (sub != null)
            Text(sub!, style: const TextStyle(color: PistakColors.textMuted)),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: color, foregroundColor: Colors.black),
            icon: const Icon(Icons.play_arrow),
            label: Text(button),
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

class _MatchTile extends ConsumerWidget {
  const _MatchTile({required this.match});
  final MatchInfo match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scheduled =
        match.status == MatchStatus.notStarted && match.scheduledAt != null;
    final subtitle = [
      scheduled
          ? l.scheduledFor(
              '${formatDate(match.scheduledAt!)} ${formatClockTime(match.scheduledAt!)}')
          : formatDate(match.displayDate),
      if (match.competition != null) match.competition!,
      if (match.category != null) match.category!,
      if (!scheduled) statusLabel(l, match.status),
    ].join(' · ');
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        title: Text(matchTitle(l, match),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle),
        leading: scheduled
            ? const Icon(Icons.event, color: PistakColors.home)
            : Text(
                '${match.homeScore}-${match.awayScore}',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    fontFeatures: tabularFigures),
              ),
        trailing: PopupMenuButton<String>(
          onSelected: (_) => _delete(context, ref, l),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'delete', child: Text(l.deleteMatch)),
          ],
        ),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => match.status == MatchStatus.finished
              ? MatchSummaryScreen(matchId: match.id)
              : MatchScreen(matchId: match.id),
        )),
      ),
    );
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, AppLocalizations l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l.deleteMatchConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: PistakColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.deleteAction)),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(matchRepositoryProvider).deleteMatch(match.id);
    }
  }
}

/// History filters: team, competition, category, dates, result.
class FilterSheet extends ConsumerWidget {
  const FilterSheet({super.key, required this.matches});
  final List<MatchInfo> matches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final f = ref.watch(matchFilterProvider);
    final teams = ref.watch(teamsProvider).valueOrNull ?? const <Team>[];
    void set(MatchFilter v) => ref.read(matchFilterProvider.notifier).state = v;
    final competitions = {
      for (final m in matches)
        if (m.competition != null) m.competition!
    }.toList()
      ..sort();
    final categories = {
      for (final m in matches)
        if (m.category != null) m.category!
    }.toList()
      ..sort();

    Widget chips<T>(String title, List<T> values, T? selected,
            String Function(T) label, void Function(T?) onSelect) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                label: Text(l.all),
                selected: selected == null,
                onSelected: (_) => onSelect(null),
              ),
              for (final v in values)
                ChoiceChip(
                  label: Text(label(v)),
                  selected: v == selected,
                  onSelected: (_) => onSelect(v),
                ),
            ]),
          ],
        );

    final from = f.from;
    final to = f.to;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.filters, style: Theme.of(context).textTheme.titleLarge),
              if (teams.isNotEmpty)
                chips<Team>(
                    l.team,
                    teams,
                    f.team,
                    (t) => t.name,
                    (t) => set(f.copyWith(
                        team: t,
                        clearTeam: t == null,
                        clearResult: t == null))),
              if (competitions.isNotEmpty)
                chips<String>(
                    l.fieldCompetition,
                    competitions,
                    f.competition,
                    (s) => s,
                    (s) => set(f.copyWith(
                        competition: s, clearCompetition: s == null))),
              if (categories.isNotEmpty)
                chips<String>(
                    l.fieldCategory,
                    categories,
                    f.category,
                    (s) => s,
                    (s) =>
                        set(f.copyWith(category: s, clearCategory: s == null))),
              if (f.team != null)
                chips<ResultFilter>(
                    l.filterResult,
                    ResultFilter.values,
                    f.result,
                    (r) => switch (r) {
                          ResultFilter.win => l.resultWin,
                          ResultFilter.draw => l.resultDraw,
                          ResultFilter.loss => l.resultLoss,
                        },
                    (r) => set(f.copyWith(result: r, clearResult: r == null))),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(from == null || to == null
                      ? l.filterDates
                      : '${formatDate(from)} – ${formatDate(to)}'),
                  onPressed: () async {
                    final now = DateTime.now();
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(now.year + 5),
                      initialDateRange: from == null || to == null
                          ? null
                          : DateTimeRange(start: from, end: to),
                    );
                    if (range != null) {
                      set(f.copyWith(from: range.start, to: range.end));
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => set(const MatchFilter()),
                child: Text(l.clearFilters),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
