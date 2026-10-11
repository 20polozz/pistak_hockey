import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/audio/audio_recording.dart';
import '../../domain/team/team.dart';
import '../../domain/match/match_event.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../widgets/event_button.dart';
import '../widgets/event_labels.dart';
import '../../domain/match/event_clock.dart';

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
    final pendingTranscript = e.subtype == IncidentKinds.voice &&
        e.text == null &&
        e.metadata[MetaKeys.transcriptStatus] != 'done';
    tiles.add(_TimelineTile(
      event: e,
      clock: formatMatchTime(v.info.format.clockOf(e)),
      editable: onTap != null,
      note: pendingTranscript ? l.transcriptPending : null,
      title: eventLabel(l, e),
      team: e.team == null
          ? null
          : [
              teamName(l, v.info, e.team!),
              if (e.playerName != null) e.playerName!,
              if (e.assistName != null) '${l.assist}: ${e.assistName}',
            ].join(' · '),
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
          IconButton(
            tooltip: l.showVoided,
            isSelected: _showVoided,
            icon: const Icon(Icons.visibility_off_outlined),
            selectedIcon: const Icon(Icons.visibility),
            onPressed: () => setState(() => _showVoided = !_showVoided),
          ),
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
                itemCount: tiles.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) => i == 0
                    ? Row(children: [
                        const Icon(Icons.edit_outlined,
                            size: 16, color: PistakColors.textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(l.timelineEditHint,
                              style: const TextStyle(
                                  fontSize: 13, color: PistakColors.textMuted)),
                        ),
                      ])
                    : tiles[i - 1],
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
    required this.clock,
    required this.title,
    this.editable = false,
    this.team,
    this.score,
    this.voidedLabel,
    this.note,
    this.onTap,
  });

  final MatchEvent event;
  final String clock;
  final bool editable;
  final String title;
  final String? team;
  final String? score;
  final String? voidedLabel;
  final String? note;
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
                    clock,
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
                      if (note != null)
                        Text(note!,
                            style: const TextStyle(
                                fontStyle: FontStyle.italic,
                                color: PistakColors.warning,
                                fontSize: 12)),
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
                if (editable)
                  const Padding(
                    padding: EdgeInsets.only(left: 8, top: 2),
                    child: Icon(Icons.edit_outlined,
                        size: 18, color: PistakColors.textMuted),
                  ),
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
  late final _time = TextEditingController(
      text: formatMatchTime(widget.view.info.format.clockOf(widget.event)));
  late final _text = TextEditingController(text: widget.event.text ?? '');
  String? _timeError;
  late String? _playerId = e.metadata[MetaKeys.playerId] as String?;
  late String? _playerName = e.playerName;
  late String? _assistId = switch (e.metadata[MetaKeys.assistId]) {
    final String v when v.isNotEmpty => v,
    _ => null,
  };
  late String? _assistName = e.assistName;
  late String? _cardColor = e.subtype;
  late String? _shotKind = e.shotKind;

  List<TeamMember> _players() {
    final info = widget.view.info;
    final teamId = switch (_team) {
      TeamSide.home => info.homeTeamId,
      TeamSide.away => info.awayTeamId,
      null => null,
    };
    if (teamId == null) return const [];
    return (ref.watch(teamMembersProvider(teamId)).valueOrNull ??
            const <TeamMember>[])
        .where((m) => e.type == EventTypes.save
            ? m.role == MemberRole.goalkeeper
            : m.role == MemberRole.player || m.role == MemberRole.goalkeeper)
        .toList();
  }

  /// Optional: only shown when the event's side is linked to one of the
  /// user's teams that has players.
  Widget _memberPicker(String label, String emptyLabel, String? selected,
      void Function(String? id, String? name) onChanged) {
    final members = _players();
    if (members.isEmpty) return const SizedBox.shrink();
    final value = members.any((m) => m.id == selected) ? selected : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String?>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem<String?>(value: null, child: Text(emptyLabel)),
          for (final m in members)
            DropdownMenuItem<String?>(value: m.id, child: Text(m.label)),
        ],
        onChanged: (id) => setState(() =>
            onChanged(id, members.where((m) => m.id == id).firstOrNull?.label)),
      ),
    );
  }

  MatchEvent get e => widget.event;

  bool get _hasTeam => const {
        EventTypes.goal,
        EventTypes.foul,
        EventTypes.card,
        EventTypes.timeout,
        EventTypes.save,
        EventTypes.shot,
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
            if (e.type == EventTypes.card) ...[
              SegmentedButton<String>(
                segments: [
                  for (final c in const [
                    CardColors.yellow,
                    CardColors.blue,
                    CardColors.red
                  ])
                    ButtonSegment(
                      value: c,
                      icon: MiniCard(color: cardColor(c), height: 18),
                      label: Text(switch (c) {
                        CardColors.yellow => l.cardYellow,
                        CardColors.blue => l.cardBlue,
                        _ => l.cardRed,
                      }),
                    ),
                ],
                selected: {_cardColor ?? CardColors.yellow},
                onSelectionChanged: (s) => setState(() => _cardColor = s.first),
              ),
              const SizedBox(height: 16),
            ],
            if (_shotKind != null) ...[
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                      value: ShotKinds.penalty, label: Text(l.penalty)),
                  ButtonSegment(
                      value: ShotKinds.freeHit, label: Text(l.freeHit)),
                ],
                selected: {_shotKind!},
                onSelectionChanged: (s) => setState(() => _shotKind = s.first),
              ),
              const SizedBox(height: 16),
            ],
            _memberPicker(e.type == EventTypes.save ? l.whoSaved : l.player,
                l.noPlayer, _playerId, (id, name) {
              _playerId = id;
              _playerName = name;
            }),
            if (e.type == EventTypes.goal && e.shotKind == null)
              _memberPicker(l.assist, l.noAssist, _assistId, (id, name) {
                _assistId = id;
                _assistName = name;
              }),
          ],
          if (!_isClock) ...[
            TextField(
              controller: _time,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                  labelText: l.eventClockField, errorText: _timeError),
            ),
            const SizedBox(height: 16),
          ],
          if (e.metadata[MetaKeys.audioId] is String) ...[
            _AudioControls(audioId: e.metadata[MetaKeys.audioId] as String),
            const SizedBox(height: 12),
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
    final clock = parseMatchTime(_time.text);
    final f = widget.view.info.format;
    final p = e.period < 1 ? 1 : e.period;
    if (clock == null || clock > f.durationOf(p)) {
      setState(() => _timeError = l.invalidTime);
      return;
    }
    final meta = Map<String, dynamic>.of(e.metadata);
    if (_playerId == null) {
      meta.remove(MetaKeys.playerId);
      meta.remove(MetaKeys.playerName);
    } else {
      meta[MetaKeys.playerId] = _playerId;
      meta[MetaKeys.playerName] = _playerName;
    }
    if (_shotKind != null) meta[MetaKeys.shotKind] = _shotKind;
    if (e.type == EventTypes.goal &&
        e.shotKind == null &&
        _players().isNotEmpty) {
      meta[MetaKeys.assistId] = _assistId ?? '';
      if (_assistName == null) {
        meta.remove(MetaKeys.assistName);
      } else {
        meta[MetaKeys.assistName] = _assistName;
      }
    }
    var subtype = e.type == EventTypes.card ? _cardColor : e.subtype;
    if (e.type == EventTypes.incident) {
      final t = _text.text.trim();
      if (t.isEmpty) {
        meta.remove(MetaKeys.text);
      } else {
        meta[MetaKeys.text] = t;
        if (subtype == IncidentKinds.unjustified) subtype = IncidentKinds.text;
      }
    }
    // The field shows the clock (time left); store elapsed times.
    final periodTime = f.periodTimeForClock(p, clock);
    final time =
        (e.period > 0 ? f.startOf(e.period) : Duration.zero) + periodTime;
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

/// Play / delete the audio of a voice incident.
class _AudioControls extends ConsumerStatefulWidget {
  const _AudioControls({required this.audioId});
  final String audioId;

  @override
  ConsumerState<_AudioControls> createState() => _AudioControlsState();
}

class _AudioControlsState extends ConsumerState<_AudioControls> {
  AudioRecording? _rec;
  bool _loaded = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await ref.read(audioRepositoryProvider).get(widget.audioId);
    if (!mounted) return;
    setState(() {
      _rec = r;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final rec = _rec;
    if (!_loaded) return const LinearProgressIndicator();
    if (rec == null || !rec.hasAudio) {
      return Text(l.audioDeleted,
          style: const TextStyle(color: PistakColors.textMuted));
    }
    final status = switch (rec.transcriptStatus) {
      TranscriptStatus.pending => l.transcriptPending,
      TranscriptStatus.failed => l.transcriptFailed,
      TranscriptStatus.done => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          FilledButton.tonalIcon(
            onPressed: () async {
              final player = ref.read(playbackServiceProvider);
              if (_playing) {
                await player.stop();
              } else {
                await player.play(rec.bytes!, mimeType: rec.mimeType);
              }
              if (mounted) setState(() => _playing = !_playing);
            },
            icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
            label: Text(_playing ? l.stopAudio : l.playAudio),
          ),
          const SizedBox(width: 8),
          Text(formatMatchTime(rec.duration),
              style: const TextStyle(fontFeatures: tabularFigures)),
          const Spacer(),
          IconButton(
            tooltip: l.deleteAudio,
            icon: const Icon(Icons.delete_outline, color: PistakColors.danger),
            onPressed: () async {
              await ref.read(playbackServiceProvider).stop();
              await ref.read(audioRepositoryProvider).deleteAudio(rec.id);
              await _load();
            },
          ),
        ]),
        if (status != null)
          Text(status,
              style:
                  const TextStyle(fontSize: 12, color: PistakColors.textMuted)),
      ],
    );
  }
}
