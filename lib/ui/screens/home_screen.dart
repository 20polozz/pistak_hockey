import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/match/match_info.dart';
import '../../domain/sport/sports.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../widgets/event_labels.dart';
import '../widgets/sync_badge.dart';
import 'match_screen.dart';
import 'match_summary_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final active = ref.watch(activeMatchProvider).valueOrNull;
    final matches = ref.watch(matchesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PISTAK',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3)),
        actions: [
          const SyncBadge(),
          IconButton(
            tooltip: l.settings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (active != null) ...[
                _ActiveMatchCard(match: active),
                const SizedBox(height: 16),
              ],
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(72)),
                icon: const Icon(Icons.add_circle_outline, size: 28),
                label: Text(l.newMatch, style: const TextStyle(fontSize: 20)),
                onPressed: () => _newMatch(context, ref),
              ),
              const SizedBox(height: 28),
              Text(l.myMatches, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ...matches.when<List<Widget>>(
                loading: () => [const LinearProgressIndicator()],
                error: (e, _) => [Text('$e')],
                data: (list) => list.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(l.noMatchesYet,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: PistakColors.textMuted)),
                        ),
                      ]
                    : [
                        for (final m in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _MatchTile(match: m),
                          ),
                      ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// NEW MATCH: creates an untitled match instantly (no form to fill) and
  /// opens the recording screen. Details can be completed later.
  Future<void> _newMatch(BuildContext context, WidgetRef ref) async {
    final sport = Sports.defaultSport;
    final format =
        await ref.read(settingsRepositoryProvider).lastFormat() ??
            sport.defaultFormat;
    final match = await ref
        .read(matchRepositoryProvider)
        .createMatch(sport: sport.id, format: format);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MatchScreen(matchId: match.id)));
  }
}

class _ActiveMatchCard extends StatelessWidget {
  const _ActiveMatchCard({required this.match});
  final MatchInfo match;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PistakColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PistakColors.accent, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.fiber_manual_record,
                color: PistakColors.danger, size: 14),
            const SizedBox(width: 6),
            Text(l.matchInProgress.toUpperCase(),
                style: const TextStyle(
                    fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          ]),
          const SizedBox(height: 8),
          Text(matchTitle(l, match),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text('${match.homeScore} – ${match.awayScore}',
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  fontFeatures: tabularFigures)),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: Text(l.continueMatch),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => MatchScreen(matchId: match.id))),
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
    final subtitle = [
      formatDate(match.displayDate),
      if (match.competition != null) match.competition!,
      if (match.category != null) match.category!,
      statusLabel(l, match.status),
    ].join(' · ');
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        title: Text(matchTitle(l, match),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle),
        leading: Text(
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
              style: FilledButton.styleFrom(
                  backgroundColor: PistakColors.danger),
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
