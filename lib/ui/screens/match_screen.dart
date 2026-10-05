import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/match/event_factory.dart';
import '../../domain/match/match_event.dart';
import '../../domain/match/match_state.dart';
import '../../domain/sport/sports.dart';
import '../../l10n/app_localizations.dart';
import '../../services/match_session_service.dart';
import '../match_controller.dart';
import '../providers.dart';
import '../widgets/event_button.dart';
import '../widgets/event_labels.dart';
import '../widgets/sync_badge.dart';
import '../widgets/ticker.dart';
import '../widgets/voice_recorder_dialog.dart';
import 'match_details_screen.dart';
import 'match_summary_screen.dart';
import 'timeline_screen.dart';

/// Live recording screen. Priorities: time, period, score, big buttons.
class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

enum _MenuAction { details, timeline, adjustClock, summary, endMatch }

class _MatchScreenState extends ConsumerState<MatchScreen> {
  late final MatchSessionService _session;

  @override
  void initState() {
    super.initState();
    _session = ref.read(sessionServiceProvider);
    _session.keepScreenOn(true);
  }

  @override
  void dispose() {
    _session.keepScreenOn(false);
    super.dispose();
  }

  MatchController get _controller =>
      ref.read(matchControllerProvider(widget.matchId));

  /// Runs an action with immediate haptic feedback; errors are always shown.
  Future<void> _run(Future<Object?> Function(MatchController c) action,
      {bool heavy = false}) async {
    heavy ? _session.heavy() : _session.tap();
    try {
      await action(_controller);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: PistakColors.danger,
        content: Text('$e'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final view = ref.watch(matchViewProvider(widget.matchId));
    return view.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('$e')),
      ),
      data: (v) => _buildMatch(context, l, v),
    );
  }

  Widget _buildMatch(BuildContext context, AppLocalizations l, MatchView v) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Text(
          matchTitle(l, v.info),
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          SyncBadge(compact: MediaQuery.sizeOf(context).width < 600),
          IconButton(
            tooltip: l.timeline,
            icon: const Icon(Icons.timeline),
            onPressed: () => _open(TimelineScreen(matchId: widget.matchId)),
          ),
          PopupMenuButton<_MenuAction>(
            onSelected: (a) => _onMenu(a, l, v),
            itemBuilder: (_) => [
              PopupMenuItem(value: _MenuAction.details, child: Text(l.matchDetails)),
              PopupMenuItem(value: _MenuAction.timeline, child: Text(l.timeline)),
              if (v.state.period > 0 && !v.state.isFinished)
                PopupMenuItem(
                    value: _MenuAction.adjustClock, child: Text(l.adjustClock)),
              PopupMenuItem(value: _MenuAction.summary, child: Text(l.summary)),
              if (v.state.isStarted && !v.state.isFinished)
                PopupMenuItem(value: _MenuAction.endMatch, child: Text(l.endMatch)),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final banner = _Banner(
              view: v, onEndTimeout: () => _run((c) => c.endTimeout()));
          // Tablets / desktop browsers in landscape: info left, buttons right.
          if (c.maxWidth >= 900 && c.maxWidth > c.maxHeight) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 380,
                    child: Column(
                      children: [
                        _Scoreboard(view: v),
                        banner,
                        const Spacer(),
                        _controls(l, v),
                        const SizedBox(height: 8),
                        _lastEventBar(l, v),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: _grid(l, v)),
                ],
              ),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Column(
                  children: [
                    _Scoreboard(view: v),
                    banner,
                    const SizedBox(height: 8),
                    Expanded(child: _grid(l, v)),
                    const SizedBox(height: 8),
                    _controls(l, v),
                    const SizedBox(height: 8),
                    _lastEventBar(l, v),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ------------------------------------------------------------ buttons

  Widget _grid(AppLocalizations l, MatchView v) {
    final s = v.state;
    if (s.isShootout) return _shootoutPanel(l, v);
    final sport = Sports.byId(v.info.sport);
    final period = s.period < 1 ? 1 : s.period;
    final maxTo = s.format.timeoutsPerTeamPerPeriod;

    String toLabel(TeamSide side) =>
        '${s.tally(side).timeoutsIn(period)}/$maxTo';

    final rows = <(int, List<Widget>)>[
      (3, [
        EventButton(
          label: l.goalHome,
          icon: Icons.sports_hockey,
          color: PistakColors.home,
          filled: true,
          onTap: () => _run((c) => c.goal(TeamSide.home), heavy: true),
        ),
        EventButton(
          label: l.goalAway,
          icon: Icons.sports_hockey,
          color: PistakColors.away,
          filled: true,
          onTap: () => _run((c) => c.goal(TeamSide.away), heavy: true),
        ),
      ]),
      (2, [
        EventButton(
          label: l.foulHome,
          icon: Icons.front_hand,
          color: PistakColors.home,
          onTap: () => _run((c) => c.foul(TeamSide.home)),
        ),
        EventButton(
          label: l.foulAway,
          icon: Icons.front_hand,
          color: PistakColors.away,
          onTap: () => _run((c) => c.foul(TeamSide.away)),
        ),
      ]),
      (2, [
        for (final color in sport.cardColors)
          EventButton(
            label: _cardLabel(l, color),
            icon: Icons.style,
            color: cardColor(color),
            onTap: () => _run((c) => c.card(color)),
          ),
      ]),
      (2, [
        EventButton(
          label: l.timeoutHome,
          sublabel: toLabel(TeamSide.home),
          icon: Icons.timer_outlined,
          color: PistakColors.home,
          onTap: () => _run((c) => c.timeout(TeamSide.home)),
        ),
        EventButton(
          label: l.timeoutAway,
          sublabel: toLabel(TeamSide.away),
          icon: Icons.timer_outlined,
          color: PistakColors.away,
          onTap: () => _run((c) => c.timeout(TeamSide.away)),
        ),
      ]),
      (2, [
        EventButton(
          label: l.incident,
          icon: Icons.report_problem_outlined,
          color: PistakColors.incident,
          onTap: () => _openIncidentSheet(l),
        ),
      ]),
    ];

    Widget row(List<Widget> children) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: children[i]),
            ],
          ],
        );

    const gap = 8.0;
    const minRow = 56.0;
    return LayoutBuilder(builder: (context, c) {
      final needed = rows.length * minRow + (rows.length - 1) * gap;
      if (c.maxHeight >= needed) {
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: gap),
              Expanded(flex: rows[i].$1, child: row(rows[i].$2)),
            ],
          ],
        );
      }
      // Very short screens (landscape phones): scroll instead of shrinking
      // buttons below a comfortable touch size.
      return ListView(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: gap),
            SizedBox(height: 64, child: row(rows[i].$2)),
          ],
        ],
      );
    });
  }

  /// Penalty shoot-out: one column per team, SCORED / MISSED.
  Widget _shootoutPanel(AppLocalizations l, MatchView v) {
    final s = v.state;
    Widget column(TeamSide side) {
      final t = s.tally(side);
      final color = teamColor(side);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(teamName(l, v.info, side).toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          Text('${t.shootoutScored} / ${t.shootoutAttempts}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  fontFeatures: tabularFigures)),
          const SizedBox(height: 8),
          Expanded(
            child: EventButton(
              label: l.penaltyScored,
              icon: Icons.check_circle_outline,
              color: color,
              filled: true,
              onTap: () => _run((c) => c.shootoutAttempt(side, scored: true),
                  heavy: true),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: EventButton(
              label: l.penaltyMissed,
              icon: Icons.cancel_outlined,
              color: color,
              onTap: () =>
                  _run((c) => c.shootoutAttempt(side, scored: false)),
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: column(TeamSide.home)),
        const SizedBox(width: 8),
        Expanded(child: column(TeamSide.away)),
      ],
    );
  }

  String _cardLabel(AppLocalizations l, String color) => switch (color) {
        CardColors.yellow => l.cardYellow,
        CardColors.blue => l.cardBlue,
        CardColors.red => l.cardRed,
        _ => color.toUpperCase(),
      };

  Widget _controls(AppLocalizations l, MatchView v) {
    final s = v.state;
    Widget primary(String label, IconData icon, VoidCallback onTap,
            {Color color = PistakColors.accent}) =>
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(60),
          ),
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label, textAlign: TextAlign.center),
        );

    Widget secondary(String label, VoidCallback onTap) => OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(60),
            foregroundColor: Colors.white,
            side: const BorderSide(color: PistakColors.textMuted),
          ),
          onPressed: onTap,
          child: Text(label, textAlign: TextAlign.center),
        );

    final endLabel = s.hasMoreRegularPeriods
        ? l.endPeriod(s.period)
        : s.isOvertime
            ? l.endOvertime(s.period - s.format.periods)
            : l.endMatch;
    void confirmEnd() => _confirmEndPeriod(l, s);

    switch (s.phase) {
      case MatchPhase.notStarted:
        return primary(l.startMatch, Icons.play_arrow,
            () => _run((c) => c.startMatch(), heavy: true));
      case MatchPhase.running:
        return Row(children: [
          Expanded(
              flex: 3,
              child: primary(l.pauseMatch, Icons.pause,
                  () => _run((c) => c.pause()),
                  color: PistakColors.warning)),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: secondary(endLabel, confirmEnd)),
        ]);
      case MatchPhase.paused:
        return Row(children: [
          Expanded(
              flex: 3,
              child: primary(l.resumeMatch, Icons.play_arrow,
                  () => _run((c) => c.resume()))),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: secondary(endLabel, confirmEnd)),
        ]);
      case MatchPhase.periodEnded:
      case MatchPhase.onBreak:
        if (s.hasMoreRegularPeriods) {
          return primary(l.startPeriod(s.period + 1), Icons.play_arrow,
              () => _run((c) => c.startNextPeriod(), heavy: true));
        }
        // After regulation: overtime and/or shoot-out if the format allows.
        final next = s.canPlayOvertime
            ? primary(l.startOvertime(s.period + 1 - s.format.periods),
                Icons.play_arrow,
                () => _run((c) => c.startNextPeriod(), heavy: true))
            : primary(l.endMatch, Icons.flag, () => _confirmEndMatch(l));
        if (!s.format.allowShootout) return next;
        return Row(children: [
          Expanded(flex: 3, child: next),
          const SizedBox(width: 8),
          Expanded(
              flex: 2,
              child: secondary(l.startShootout,
                  () => _run((c) => c.startShootout(), heavy: true))),
        ]);
      case MatchPhase.shootout:
        return primary(l.endMatch, Icons.flag, () => _confirmEndMatch(l));
      case MatchPhase.finished:
        return primary(l.viewSummary, Icons.assessment_outlined,
            () => _open(MatchSummaryScreen(matchId: widget.matchId)));
    }
  }

  Widget _lastEventBar(AppLocalizations l, MatchView v) {
    final last = v.state.lastEvent;
    if (last == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(l.tapStartHint,
            textAlign: TextAlign.center,
            style: const TextStyle(color: PistakColors.textMuted, fontSize: 13)),
      );
    }
    final (color, icon) = eventVisual(last);
    final needsTeam = last.type == EventTypes.card && last.team == null;
    final team = last.team;
    final bar = Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: PistakColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${formatMatchTime(last.matchTime)}  ${eventLabel(l, last)}'
              '${team != null ? ' · ${teamName(l, v.info, team)}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton.icon(
            onPressed: () => _undo(l),
            icon: const Icon(Icons.undo),
            label: Text(l.undo),
          ),
        ],
      ),
    );
    if (!needsTeam) return bar;
    // One-tap card: optional team assignment right below, never blocking.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l.assignTeam,
                  style: const TextStyle(
                      fontSize: 13, color: PistakColors.textMuted)),
            ),
            _MiniTeamButton(
              label: teamName(l, v.info, TeamSide.home).toUpperCase(),
              color: PistakColors.home,
              onTap: () => _run((c) => c.setTeam(last, TeamSide.home)),
            ),
            _MiniTeamButton(
              label: teamName(l, v.info, TeamSide.away).toUpperCase(),
              color: PistakColors.away,
              onTap: () => _run((c) => c.setTeam(last, TeamSide.away)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        bar,
      ],
    );
  }

  // ------------------------------------------------------------ actions

  Future<void> _undo(AppLocalizations l) async {
    _session.tap();
    final messenger = ScaffoldMessenger.of(context);
    final undone = await _controller.undo();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text(undone.isEmpty
          ? l.nothingToUndo
          : l.undone(eventLabel(l, undone.first))),
    ));
  }

  Future<void> _confirmEndPeriod(AppLocalizations l, MatchState s) async {
    if (s.hasMoreRegularPeriods) {
      final ok = await _confirm(l, l.confirmEndPeriod(s.period));
      if (ok) await _run((c) => c.endPeriod(), heavy: true);
      return;
    }
    final canOvertime = s.canPlayOvertime;
    final canShootout = s.format.allowShootout;
    if (!canOvertime && !canShootout) {
      final ok = await _confirm(l, l.confirmEndMatch);
      if (ok) await _run((c) => c.endPeriod(), heavy: true);
      return;
    }
    // Last period: the scorer decides (draw → overtime / penalties).
    final choice = await showDialog<PeriodEndChoice>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.chooseAfterPeriod),
        children: [
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            onPressed: () => Navigator.pop(ctx, PeriodEndChoice.endMatch),
            child: Text(l.optEndMatch,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          if (canOvertime)
            SimpleDialogOption(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              onPressed: () => Navigator.pop(ctx, PeriodEndChoice.overtime),
              child: Text(l.optOvertime),
            ),
          if (canShootout)
            SimpleDialogOption(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              onPressed: () => Navigator.pop(ctx, PeriodEndChoice.shootout),
              child: Text(l.optShootout),
            ),
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.cancel,
                style: const TextStyle(color: PistakColors.textMuted)),
          ),
        ],
      ),
    );
    if (choice != null) {
      await _run((c) => c.endPeriod(then: choice), heavy: true);
    }
  }

  Future<void> _confirmEndMatch(AppLocalizations l) async {
    final ok = await _confirm(l, l.confirmEndMatch);
    if (ok) await _run((c) => c.endMatch(), heavy: true);
  }

  Future<bool> _confirm(AppLocalizations l, String title) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(l.confirmEndBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.confirm)),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _openIncidentSheet(AppLocalizations l) async {
    // The incident happens NOW, not when the user finishes typing.
    final at = ref.read(clockProvider).now();
    _session.tap();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(l.incidentTitle,
                  style: Theme.of(ctx).textTheme.titleLarge),
            ),
            ListTile(
              minTileHeight: 64,
              leading: const Icon(Icons.flash_on),
              title: Text(l.incidentUnjustifiedAction),
              onTap: () => Navigator.pop(ctx, IncidentKinds.unjustified),
            ),
            ListTile(
              minTileHeight: 64,
              leading: const Icon(Icons.edit_note),
              title: Text(l.incidentWritten),
              onTap: () => Navigator.pop(ctx, IncidentKinds.text),
            ),
            ListTile(
              minTileHeight: 64,
              leading: const Icon(Icons.mic_none),
              title: Text(l.incidentVoice),
              subtitle: Text(l.incidentVoiceHint),
              onTap: () => Navigator.pop(ctx, IncidentKinds.voice),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == IncidentKinds.unjustified) {
      await _run((c) => c.incident(IncidentKinds.unjustified, at: at));
      return;
    }
    if (choice == IncidentKinds.voice) {
      await _recordVoice(l, at);
      return;
    }
    final text = await _askText(l.incidentWritten, l.incidentWrittenHint);
    if (!mounted) return;
    // Even with an empty text we keep the record: it happened.
    await _run((c) => c.incident(
        (text ?? '').trim().isEmpty
            ? IncidentKinds.unjustified
            : IncidentKinds.text,
        text: text,
        at: at));
  }

  Future<void> _recordVoice(AppLocalizations l, DateTime at) async {
    final result = await VoiceRecorderDialog.show(context);
    if (!mounted) return;
    final audio = result?.audio;
    if (audio != null && audio.wav.length > 44) {
      await _run((c) => c.voiceIncident(
            bytes: audio.wav,
            mimeType: audio.mimeType,
            duration: audio.duration,
            at: at,
          ));
      // Try to transcribe in the background (no-op while offline).
      ref.read(transcriptionQueueProvider).processPending();
      return;
    }
    // No audio (cancelled, no permission, no mic): the moment is still kept.
    await _run((c) => c.incident(IncidentKinds.unjustified, at: at));
    if (result?.error != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.micUnavailable)));
    }
  }

  Future<String?> _askText(String title, String hint) {
    final ctrl = TextEditingController();
    final l = AppLocalizations.of(context);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(l.save)),
        ],
      ),
    );
  }

  Future<void> _adjustClock(AppLocalizations l, MatchState s) async {
    final now = ref.read(clockProvider).now();
    final ctrl =
        TextEditingController(text: formatMatchTime(s.periodElapsedAt(now)));
    final value = await showDialog<Duration>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(l.adjustClock),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                  labelText: l.adjustClockHint, errorText: error),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l.cancel)),
              FilledButton(
                onPressed: () {
                  final d = parseMatchTime(ctrl.text);
                  if (d == null) {
                    setState(() => error = l.invalidTime);
                  } else {
                    Navigator.pop(ctx, d);
                  }
                },
                child: Text(l.save),
              ),
            ],
          ),
        );
      },
    );
    if (value != null) await _run((c) => c.adjustClock(value));
  }

  void _onMenu(_MenuAction a, AppLocalizations l, MatchView v) {
    switch (a) {
      case _MenuAction.details:
        _open(MatchDetailsScreen(matchId: widget.matchId));
      case _MenuAction.timeline:
        _open(TimelineScreen(matchId: widget.matchId));
      case _MenuAction.adjustClock:
        _adjustClock(l, v.state);
      case _MenuAction.summary:
        _open(MatchSummaryScreen(matchId: widget.matchId));
      case _MenuAction.endMatch:
        _confirmEndMatch(l);
    }
  }

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}

// ---------------------------------------------------------------- widgets

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.view});
  final MatchView view;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = view.state;
    final phaseText = switch (s.phase) {
      MatchPhase.notStarted => l.notStartedLabel,
      MatchPhase.running ||
      MatchPhase.paused ||
      MatchPhase.periodEnded =>
        s.isOvertime
            ? l.overtimeLabel(s.period - s.format.periods)
            : l.periodLabel(s.period),
      MatchPhase.shootout => l.shootoutLabel,
      MatchPhase.onBreak => l.breakLabel,
      MatchPhase.finished => l.finishedLabel,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: PistakColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          TickerBuilder(builder: (context, now) {
            final over = s.isOvertimeAt(now);
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (s.phase == MatchPhase.paused)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.pause_circle_filled,
                        color: PistakColors.warning, size: 32),
                  ),
                Text(
                  formatMatchTime(s.matchTimeAt(now)),
                  semanticsLabel: formatMatchTime(s.matchTimeAt(now)),
                  style: TextStyle(
                    fontSize: 64,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    fontFeatures: tabularFigures,
                    color: over
                        ? PistakColors.warning
                        : s.isClockRunning
                            ? Colors.white
                            : PistakColors.textMuted,
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 2),
          Text(phaseText,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: PistakColors.accent)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _TeamScore(view: view, side: TeamSide.home)),
              const Text('–',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.w300)),
              Expanded(child: _TeamScore(view: view, side: TeamSide.away)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TeamScore extends StatelessWidget {
  const _TeamScore({required this.view, required this.side});
  final MatchView view;
  final TeamSide side;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = view.state;
    final t = s.tally(side);
    final period = s.period < 1 ? 1 : s.period;
    final color = teamColor(side);
    return Column(
      children: [
        Text(
          teamName(l, view.info, side).toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w800, letterSpacing: 0.8),
        ),
        Text(
          '${t.goals}',
          style: const TextStyle(
              fontSize: 48,
              height: 1.1,
              fontWeight: FontWeight.w900,
              fontFeatures: tabularFigures),
        ),
        if (s.hadShootout)
          Text(l.shootoutScore(s.home.shootoutScored, s.away.shootoutScored),
              style: const TextStyle(
                  fontSize: 12, color: PistakColors.accent)),
        _foulsLine(l, s, t, period),
        // Blue-card exclusions: countdown of played time, never colour-only.
        TickerBuilder(
          interval: const Duration(milliseconds: 500),
          builder: (context, now) {
            final active = s.activeExclusionsAt(now, team: side);
            if (active.isEmpty) return const SizedBox(height: 16);
            return Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              children: [
                for (final (_, left) in active)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: PistakColors.blueCard.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: PistakColors.blueCard),
                    ),
                    child: Text('⏱ ${formatMatchTime(left)}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            fontFeatures: tabularFigures)),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _foulsLine(
      AppLocalizations l, MatchState s, TeamTally t, int period) {
    final limit = s.format.foulLimit;
    final reached = s.foulLimitReached(side);
    final near = s.foulLimitNear(side);
    final fouls = limit == null
        ? '${t.foulsIn(period)}'
        : '${t.foulsIn(period)}/$limit';
    return Text(
      '${l.foulsShort} $fouls${reached ? ' ⚠' : ''} · ${l.timeoutsShort} ${t.timeoutsIn(period)}',
      semanticsLabel: reached ? l.foulLimitReached : null,
      style: TextStyle(
        fontSize: 12,
        fontWeight: reached || near ? FontWeight.w800 : FontWeight.w400,
        color: reached
            ? PistakColors.danger
            : near
                ? PistakColors.warning
                : PistakColors.textMuted,
      ),
    );
  }
}

/// Timeout countdown or break timer.
class _Banner extends StatelessWidget {
  const _Banner({required this.view, required this.onEndTimeout});
  final MatchView view;
  final VoidCallback onEndTimeout;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = view.state;
    final timeout = s.activeTimeout;
    if (s.isInPlay && timeout != null) {
      return _bar(
        PistakColors.warning,
        Icons.timer_outlined,
        (now) => l.timeoutBanner(teamName(l, view.info, timeout.team),
            formatMatchTime(s.timeoutRemainingAt(now) ?? Duration.zero)),
        action: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: PistakColors.warning,
            foregroundColor: Colors.black,
            minimumSize: const Size(0, 44),
          ),
          onPressed: onEndTimeout,
          child: Text(l.endTimeout),
        ),
      );
    }
    if (s.phase == MatchPhase.onBreak) {
      return _bar(
        PistakColors.accent,
        Icons.hourglass_bottom,
        (now) => l.breakBanner(
            '${formatMatchTime(s.breakElapsedAt(now) ?? Duration.zero)} / ${formatMatchTime(s.format.breakDuration)}'),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _bar(Color color, IconData icon, String Function(DateTime) text,
          {Widget? action}) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color),
          ),
          child: TickerBuilder(
            builder: (context, now) => Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(text(now),
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontFeatures: tabularFigures)),
                ),
                if (action != null) action,
              ],
            ),
          ),
        ),
      );
}

class _MiniTeamButton extends StatelessWidget {
  const _MiniTeamButton(
      {required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 40),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            foregroundColor: color,
            side: BorderSide(color: color),
          ),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      );
}
