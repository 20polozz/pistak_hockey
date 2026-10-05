import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/match/match_event.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../widgets/event_labels.dart';

/// Builds the chronological list. Goals show the running score.
List<Widget> buildTimelineTiles(
  BuildContext context,
  MatchView v, {
  bool showVoided = false,
  void Function(MatchEvent e)? onTap,
}) {
  final l = AppLocalizations.of(context);
  var home = 0;
  var away = 0;
  final tiles = <Widget>[];
  for (final e in v.events) {
    if (e.isVoided && !showVoided) continue;
    String? score;
    if (e.type == EventTypes.goal && !e.isVoided) {
      if (e.team == TeamSide.home) home++;
      if (e.team == TeamSide.away) away++;
      score = l.scoreAfter(home, away);
    }
    tiles.add(_TimelineTile(
      event: e,
      title: eventLabel(l, e),
      team: e.team == null ? null : teamName(l, v.info, e.team!),
      score: score,
      voidedLabel: e.isVoided ? l.voided : null,
      onTap: onTap == null ? null : () => onTap(e),
    ));
  }
  return tiles;
}

class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  bool _showVoided = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final view = ref.watch(matchViewProvider(widget.matchId));
    return Scaffold(
      appBar: AppBar(
        title: Text(l.timeline),
        actions: [
          Row(children: [
            Text(l.showVoided, style: const TextStyle(fontSize: 12)),
            Switch(
              value: _showVoided,
              onChanged: (v) => setState(() => _showVoided = v),
            ),
          ]),
        ],
      ),
      body: view.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (v) {
          final tiles = buildTimelineTiles(context, v,
              showVoided: _showVoided, onTap: (e) => _edit(e, v));
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: tiles.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) => tiles[i],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _edit(MatchEvent e, MatchView v) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EventEditSheet(event: e, view: v),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.event,
    required this.title,
    this.team,
    this.score,
    this.voidedLabel,
    this.onTap,
  });

  final MatchEvent event;
  final String title;
  final String? team;
  final String? score;
  final String? voidedLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = eventVisual(event);
    final voided = voidedLabel != null;
    final text = event.text;
    final deco = voided ? TextDecoration.lineThrough : null;
    return Opacity(
      opacity: voided ? 0.5 : 1,
      child: Material(
        color: PistakColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    formatMatchTime(event.matchTime),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        fontFeatures: tabularFigures),
                  ),
                ),
                Container(
                  width: 4,
                  height: 36,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(2)),
                ),
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [title, if (team != null) team!].join(' · '),
                        style: TextStyle(
                            fontWeight: FontWeight.w700, decoration: deco),
                      ),
                      if (text != null)
                        Text(text,
                            style: TextStyle(
                                color: PistakColors.textMuted,
                                decoration: deco)),
                      Text(
                        [
                          formatClockTime(event.timestamp),
                          if (voidedLabel != null) voidedLabel!,
                        ].join(' · '),
                        style: const TextStyle(
                            fontSize: 12, color: PistakColors.textMuted),
                      ),
                    ],
                  ),
                ),
                if (score != null)
                  Text(score!,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          fontFeatures: tabularFigures)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Edit team / time / text of an event, or delete / restore it.
class EventEditSheet extends ConsumerStatefulWidget {
  const EventEditSheet({super.key, required this.event, required this.view});
  final MatchEvent event;
  final MatchView view;

  @override
  ConsumerState<EventEditSheet> createState() => _EventEditSheetState();
}

class _EventEditSheetState extends ConsumerState<EventEditSheet> {
  late TeamSide? _team = widget.event.team;
  late final _time =
      TextEditingController(text: formatMatchTime(widget.event.matchTime));
  late final _text = TextEditingController(text: widget.event.text ?? '');
  String? _timeError;

  MatchEvent get e => widget.event;

  bool get _hasTeam => const {
        EventTypes.goal,
        EventTypes.foul,
        EventTypes.card,
        EventTypes.timeout,
      }.contains(e.type);

  bool get _isClock => EventTypes.clockTypes.contains(e.type);

  @override
  void dispose() {
    _time.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ref.read(matchControllerProvider(e.matchId));
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${l.editEvent} · ${eventLabel(l, e)}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (_hasTeam) ...[
            Text(l.team),
            const SizedBox(height: 8),
            SegmentedButton<TeamSide?>(
              segments: [
                ButtonSegment(
                    value: TeamSide.home,
                    label: Text(teamName(l, widget.view.info, TeamSide.home))),
                ButtonSegment(
                    value: TeamSide.away,
                    label: Text(teamName(l, widget.view.info, TeamSide.away))),
                if (e.type == EventTypes.card)
                  ButtonSegment(value: null, label: Text(l.noTeam)),
              ],
              selected: {_team},
              onSelectionChanged: (s) => setState(() => _team = s.first),
            ),
            const SizedBox(height: 16),
          ],
          if (!_isClock) ...[
            TextField(
              controller: _time,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                  labelText: l.matchTimeField, errorText: _timeError),
            ),
            const SizedBox(height: 16),
          ],
          if (e.type == EventTypes.incident) ...[
            TextField(
              controller: _text,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(labelText: l.textField),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor:
                        e.isVoided ? PistakColors.synced : PistakColors.danger),
                icon: Icon(e.isVoided ? Icons.restore : Icons.delete_outline),
                label: Text(e.isVoided ? l.restore : l.deleteAction),
                onPressed: () async {
                  await c.setVoided(e, !e.isVoided);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              const Spacer(),
              if (!_isClock)
                FilledButton(
                  onPressed: () => _save(l),
                  child: Text(l.save),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save(AppLocalizations l) async {
    final time = parseMatchTime(_time.text);
    if (time == null) {
      setState(() => _timeError = l.invalidTime);
      return;
    }
    final meta = Map<String, dynamic>.of(e.metadata);
    var subtype = e.subtype;
    if (e.type == EventTypes.incident) {
      final t = _text.text.trim();
      if (t.isEmpty) {
        meta.remove(MetaKeys.text);
      } else {
        meta[MetaKeys.text] = t;
        if (subtype == IncidentKinds.unjustified) subtype = IncidentKinds.text;
      }
    }
    // Keep periodTime consistent with the edited match time.
    final periodStart = e.period > 0
        ? widget.view.info.format.periodDuration * (e.period - 1)
        : Duration.zero;
    final periodTime = time - periodStart;
    final updated = e.copyWith(
      team: _team,
      clearTeam: _team == null,
      subtype: subtype,
      matchTime: time,
      periodTime: periodTime.isNegative ? Duration.zero : periodTime,
      metadata: meta,
    );
    await ref.read(matchControllerProvider(e.matchId)).updateEvent(updated);
    if (mounted) Navigator.pop(context);
  }
}
