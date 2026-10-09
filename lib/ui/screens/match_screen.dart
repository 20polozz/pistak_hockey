import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/match/event_factory.dart';
import '../../domain/match/match_event.dart';
import '../../domain/match/match_state.dart';
import '../../domain/sport/sports.dart';
import '../../domain/team/team.dart';
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
  /// Records an action, then (if that side is one of my teams with a
  /// roster) asks who did it. The event is already saved: asking never
  /// blocks or delays the recording, and can be skipped.
  Future<void> _record(
      Future<List<MatchEvent>> Function(MatchController c) action,
      {bool heavy = false}) async {
    List<MatchEvent>? events;
    await _run((c) async => events = await action(c), heavy: heavy);
    final main = events?.firstOrNull;
    if (main == null || !mounted) return;
    await _askWho(main);
  }

  Future<void> _askWho(MatchEvent e) async {
    final view = ref.read(matchViewProvider(widget.matchId)).valueOrNull;
    if (view == null) return;
    final info = view.info;
    final linked = {
      if (info.homeTeamId != null) TeamSide.home,
      if (info.awayTeamId != null) TeamSide.away,
    };
    final isCard = e.type == EventTypes.card;
    if (linked.isEmpty || (!isCard && !linked.contains(e.team))) return;
    if (!isCard &&
        !const {
          EventTypes.goal,
          EventTypes.foul,
          EventTypes.shot,
          EventTypes.save,
        }.contains(e.type)) {
      return;
    }
    final l = AppLocalizations.of(context);
    final title = switch (e.type) {
      EventTypes.goal => e.shotKind != null ? l.whoShot : l.whoScored,
      EventTypes.save => l.whoSaved,
      EventTypes.foul => l.whoFouled,
      EventTypes.shot => l.whoShot,
      _ => l.whoCard,
    };
    final who = await showModalBottomSheet<_Who>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _WhoSheet(
        view: view,
        title: title,
        side: e.team,
        chooseSide: isCard && e.team == null,
      ),
    );
    if (who == null || !mounted) return;
    final c = _controller;
    if (isCard && e.team == null && who.side != null) {
      await _run((c) => c.setTeam(e, who.side));
    }
    if (who.player != null) {
      await _run((c) => c.setMeta(e, {
            MetaKeys.playerId: who.player!.id,
            MetaKeys.playerName: who.player!.label,
          }));
    }
    // Goals: then the assist (or "no assist").
    if (e.type == EventTypes.goal &&
        e.shotKind == null &&
        who.player != null &&
        mounted) {
      final assist = await showModalBottomSheet<_Who>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _WhoSheet(
          view: view,
          title: l.whoAssisted,
          side: e.team,
          exclude: who.player!.id,
          noneLabel: l.noAssist,
        ),
      );
      if (assist == null) return;
      await c.setMeta(e, {
        MetaKeys.assistId: assist.player?.id ?? '',
        MetaKeys.assistName: assist.player?.label,
      });
    }
  }

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
          if (isBackendConfigured)
            SyncBadge(compact: MediaQuery.sizeOf(context).width < 600),
          IconButton(
            tooltip: l.timeline,
            icon: const Icon(Icons.timeline),
            onPressed: () => _open(TimelineScreen(matchId: widget.matchId)),
          ),
          PopupMenuButton<_MenuAction>(
            onSelected: (a) => _onMenu(a, l, v),
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: _MenuAction.details, child: Text(l.matchDetails)),
              PopupMenuItem(
                  value: _MenuAction.timeline, child: Text(l.timeline)),
              if (v.state.period > 0 && !v.state.isFinished)
                PopupMenuItem(
                    value: _MenuAction.adjustClock, child: Text(l.adjustClock)),
              PopupMenuItem(value: _MenuAction.summary, child: Text(l.summary)),
              if (v.state.isStarted && !v.state.isFinished)
                PopupMenuItem(
                    value: _MenuAction.endMatch, child: Text(l.endMatch)),
            ],
          ),
        ],
      ),
      // Glanceable live screen made of already-huge elements: follows the
      // system text size up to 1.5× so everything still fits one screen.
      body: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.5,
        child: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            final banner = _Banner(
                view: v,
                // End of timeout = play goes on: one tap, clock running.
                onEndTimeout: () => _run((c) async {
                      await c.endTimeout();
                      final st = await c.currentState();
                      if (st.isInPlay && !st.isClockRunning) await c.resume();
                      return null;
                    }));
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
      ),
    );
  }

  // ------------------------------------------------------------ buttons

  Widget _grid(AppLocalizations l, MatchView v) {
    final s = v.state;
    if (s.isShootout) return _shootoutPanel(l, v);
    final sport = Sports.byId(v.info.sport);
    final period = s.period < 1 ? 1 : s.period;
    // Timeouts still available this period, e.g. "1' · 30''".
    String toLabel(TeamSide side) {
      if (s.format.timeoutSlots.isEmpty) {
        return '${s.tally(side).timeoutsIn(period)}';
      }
      final left = s.timeoutsLeft(side);
      return left.isEmpty
          ? l.timeoutNoneLeft
          : left.map(formatTimeoutLength).join(' · ');
    }

    final rows = <(int, List<Widget>)>[
      (
        3,
        [
          EventButton(
            label: l.goalHome,
            icon: Icons.sports_hockey,
            color: PistakColors.home,
            filled: true,
            onTap: () => _record((c) => c.goal(TeamSide.home), heavy: true),
          ),
          EventButton(
            label: l.goalAway,
            icon: Icons.sports_hockey,
            color: PistakColors.away,
            filled: true,
            onTap: () => _record((c) => c.goal(TeamSide.away), heavy: true),
          ),
        ]
      ),
      (
        2,
        [
          EventButton(
            label: l.foulHome,
            icon: Icons.front_hand,
            color: PistakColors.home,
            onTap: () => _foul(l, v, TeamSide.home),
          ),
          EventButton(
            label: l.foulAway,
            icon: Icons.front_hand,
            color: PistakColors.away,
            onTap: () => _foul(l, v, TeamSide.away),
          ),
        ]
      ),
      if (sport.supportedEventTypes.contains(EventTypes.save))
        (
          2,
          [
            EventButton(
              label: l.saveHome,
              icon: Icons.shield_outlined,
              color: PistakColors.home,
              onTap: () => _record((c) => c.save(TeamSide.home)),
            ),
            EventButton(
              label: l.saveAway,
              icon: Icons.shield_outlined,
              color: PistakColors.away,
              onTap: () => _record((c) => c.save(TeamSide.away)),
            ),
          ]
        ),
      (
        2,
        [
          for (final color in sport.cardColors)
            CardButton(
              label: _cardLabel(l, color),
              color: cardColor(color),
              onTap: () => _record((c) => c.card(color)),
            ),
        ]
      ),
      (
        2,
        [
          EventButton(
            label: l.timeoutHome,
            sublabel: toLabel(TeamSide.home),
            icon: Icons.timer_outlined,
            color: PistakColors.home,
            onTap: () => _timeout(l, v, TeamSide.home),
          ),
          EventButton(
            label: l.timeoutAway,
            sublabel: toLabel(TeamSide.away),
            icon: Icons.timer_outlined,
            color: PistakColors.away,
            onTap: () => _timeout(l, v, TeamSide.away),
          ),
        ]
      ),
      (
        2,
        [
          EventButton(
            label: l.setPiece,
            icon: Icons.adjust,
            color: PistakColors.accent,
            onTap: () => _openSetPieceSheet(l, v),
          ),
          EventButton(
            label: l.incident,
            icon: Icons.report_problem_outlined,
            color: PistakColors.incident,
            onTap: () => _openIncidentSheet(l),
          ),
        ]
      ),
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

    const gap = 6.0;
    const minRow = 48.0;
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
            SizedBox(height: 52, child: row(rows[i].$2)),
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
              onTap: () => _run((c) => c.shootoutAttempt(side, scored: false)),
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
              child: primary(
                  l.pauseMatch, Icons.pause, () => _run((c) => c.pause()),
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
            ? primary(
                l.startOvertime(s.period + 1 - s.format.periods),
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
      return SizedBox(
        height: 56,
        child: Center(
          child: Text(l.tapStartHint,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: PistakColors.textMuted, fontSize: 13)),
        ),
      );
    }
    final (color, icon) = eventVisual(last);
    final needsTeam = last.type == EventTypes.card && last.team == null;
    final team = last.team;
    // One-tap card without team: the team buttons go inside the same bar
    // (never an extra row: the button grid must not move).
    return Container(
      height: 56,
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
              needsTeam
                  ? '${formatMatchTime(last.matchTime)}  ${eventLabel(l, last)} · ${l.assignTeam}'
                  : '${formatMatchTime(last.matchTime)}  ${eventLabel(l, last)}'
                      '${team != null ? ' · ${teamName(l, v.info, team)}' : ''}',
              maxLines: needsTeam ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: needsTeam ? 13 : 14),
            ),
          ),
          if (needsTeam) ...[
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
            IconButton(
              tooltip: l.undo,
              onPressed: () => _undo(l),
              icon: const Icon(Icons.undo, color: PistakColors.accent),
            ),
          ] else
            TextButton.icon(
              onPressed: () => _undo(l),
              icon: const Icon(Icons.undo),
              label: Text(l.undo),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ actions

  /// Penalty / direct free hit: team + kind + GOAL/MISSED. The time is the
  /// moment the button was pressed, not when the result is chosen.
  Future<void> _openSetPieceSheet(AppLocalizations l, MatchView v,
      {TeamSide? forTeam, String? title, DateTime? at}) async {
    final when = at ?? ref.read(clockProvider).now();
    if (at == null) _session.tap();
    final s = v.state;
    // After 10, 15, 20… fouls the OTHER team gets a direct free hit.
    TeamSide team = forTeam ?? TeamSide.home;
    String kind = forTeam != null ? ShotKinds.freeHit : ShotKinds.penalty;
    if (forTeam == null) {
      if (s.foulLimitReached(TeamSide.home)) {
        team = TeamSide.away;
        kind = ShotKinds.freeHit;
      } else if (s.foulLimitReached(TeamSide.away)) {
        kind = ShotKinds.freeHit;
      }
    }
    final result = await showModalBottomSheet<_SetPieceResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SetPieceSheet(
          view: v, initialTeam: team, initialKind: kind, title: title),
    );
    if (result == null) return;
    // The shooter is chosen in the same window (my team with a roster):
    // no second question afterwards.
    List<MatchEvent>? events;
    await _run(
        (c) async => events = await c.setPiece(result.team,
            kind: result.kind, scored: result.scored, at: when),
        heavy: result.scored);
    final main = events?.firstOrNull;
    final shooter = result.shooter;
    if (main != null && shooter != null) {
      await _run((c) => c.setMeta(main, {
            MetaKeys.playerId: shooter.id,
            MetaKeys.playerName: shooter.label,
          }));
    }
  }

  /// Foul; if it is the 10th, 15th, 20th… of the match, the rival's direct
  /// free hit is offered right away (who shoots + GOAL / MISSED).
  Future<void> _foul(AppLocalizations l, MatchView v, TeamSide side) async {
    final sanction = v.state.foulLimitNear(side);
    final at = ref.read(clockProvider).now();
    await _record((c) => c.foul(side));
    if (!sanction || !mounted) return;
    final rival = side.opponent;
    final now = ref.read(matchViewProvider(widget.matchId)).valueOrNull ?? v;
    await _openSetPieceSheet(l, now,
        forTeam: rival,
        title: l.freeHitDue(teamName(l, v.info, rival)),
        at: at);
  }

  /// Timeout: if both lengths (1:00 / 0:30) are left, asks which one.
  Future<void> _timeout(AppLocalizations l, MatchView v, TeamSide side) async {
    final slots = v.state.format.timeoutSlots;
    final left = v.state.timeoutsLeft(side);
    if (slots.isEmpty || left.toSet().length == 1) {
      await _run((c) => c.timeout(side));
      return;
    }
    _session.tap();
    final options =
        left.isEmpty ? slots.toSet().toList() : left.toSet().toList();
    final picked = await showModalBottomSheet<Duration>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.timeoutChoose, style: Theme.of(ctx).textTheme.titleMedium),
              Text(teamName(l, v.info, side),
                  style: TextStyle(
                      color: teamColor(side), fontWeight: FontWeight.w700)),
              if (left.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${l.timeoutsShort}: ${l.timeoutNoneLeft}',
                      style: const TextStyle(color: PistakColors.warning)),
                ),
              const SizedBox(height: 12),
              SizedBox(
                height: 72,
                child: Row(children: [
                  for (var i = 0; i < options.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: EventButton(
                        label: formatTimeoutLength(options[i]),
                        icon: Icons.timer_outlined,
                        color: teamColor(side),
                        filled: i == 0,
                        onTap: () => Navigator.pop(ctx, options[i]),
                      ),
                    ),
                  ],
                ]),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await _run((c) => c.timeout(side, duration: picked));
  }

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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              onPressed: () => Navigator.pop(ctx, PeriodEndChoice.overtime),
              child: Text(l.optOvertime),
            ),
          if (canShootout)
            SimpleDialogOption(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
              onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
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
                  onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
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

  void _open(Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => screen));
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
            // Huge clock: shrinks to fit narrow screens / large system text.
            return FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The pause icon's slot is always there (invisible while
                  // running) and mirrored on the right: pausing never
                  // rescales the clock nor moves the rest of the screen.
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Opacity(
                      opacity: s.phase == MatchPhase.paused ? 1 : 0,
                      child: const Icon(Icons.pause_circle_filled,
                          color: PistakColors.warning, size: 32),
                    ),
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
                  const SizedBox(width: 40),
                ],
              ),
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
          if (s.hadShootout)
            Text(l.shootoutScore(s.home.shootoutScored, s.away.shootoutScored),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: PistakColors.accent)),
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
        _foulsLine(l, s, t, period),
        // Goalkeeper saves of this team (whole match).
        Text(
          '${l.statSaves} ${t.saves}',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: PistakColors.textMuted),
        ),
        // Blue-card exclusions: countdown of played time, never colour-only.
        TickerBuilder(
          interval: const Duration(milliseconds: 500),
          builder: (context, now) {
            final active = s.activeExclusionsAt(now, team: side);
            // Fixed height: a blue card never makes the scoreboard (and so
            // the button grid) jump.
            if (active.isEmpty) return const SizedBox(height: 20);
            return SizedBox(
              height: 20,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (_, left) in active)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: PistakColors.blueCard.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: PistakColors.blueCard),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.timer_outlined,
                              size: 12, color: PistakColors.blueCard),
                          const SizedBox(width: 3),
                          Text(formatMatchTime(left),
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: tabularFigures)),
                        ]),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _foulsLine(AppLocalizations l, MatchState s, TeamTally t, int period) {
    final reached = s.foulLimitReached(side);
    final near = s.foulLimitNear(side);
    // Next direct free hit: 10, then 15, 20… (shows "10/10" when reached).
    final n = s.foulCount(side);
    final target = reached ? n : s.foulTarget(side);
    final fouls = target == null ? '$n' : '$n/$target';
    final color = reached
        ? PistakColors.danger
        : near
            ? PistakColors.warning
            : PistakColors.textMuted;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (reached)
        Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Icon(Icons.warning_amber_rounded,
              size: 13, color: color, semanticLabel: l.foulLimitReached),
        ),
      // Wraps (instead of overflowing) with large system text.
      Flexible(
        child: Text(
          '${l.foulsShort} $fouls · ${l.timeoutsShort} ${t.timeoutsIn(period)}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: reached || near ? FontWeight.w800 : FontWeight.w400,
            color: color,
          ),
        ),
      ),
    ]);
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
      return _TimeoutPanel(
          view: view, timeout: timeout, onEndTimeout: onEndTimeout);
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

/// Running timeout, compact (the button grid must still fit): team +
/// progress, big countdown and one RESUME button (ends the timeout and
/// restarts the clock in a single tap).
class _TimeoutPanel extends StatelessWidget {
  const _TimeoutPanel(
      {required this.view, required this.timeout, required this.onEndTimeout});
  final MatchView view;
  final ActiveTimeout timeout;
  final VoidCallback onEndTimeout;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = view.state;
    final color = teamColor(timeout.team);
    final total = timeout.duration.inMilliseconds;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: PistakColors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 2),
        ),
        child: TickerBuilder(builder: (context, now) {
          final left = s.timeoutRemainingAt(now) ?? Duration.zero;
          final over = left == Duration.zero;
          final progress =
              total <= 0 ? 0.0 : (left.inMilliseconds / total).clamp(0.0, 1.0);
          return Row(children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.timeoutOf(
                        teamName(l, view.info, timeout.team).toUpperCase()),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.3),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatMatchTime(left),
                    style: TextStyle(
                        color: over ? PistakColors.danger : Colors.white,
                        fontSize: 26,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        fontFeatures: tabularFigures),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      color: over ? PistakColors.danger : color,
                      backgroundColor: color.withValues(alpha: 0.2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: l.endTimeout,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: PistakColors.accent,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(0, 56),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.w800, letterSpacing: 0.4),
                ),
                onPressed: onEndTimeout,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(l.resumeMatch),
              ),
            ),
          ]);
        }),
      ),
    );
  }
}

typedef _SetPieceResult = ({
  TeamSide team,
  String kind,
  bool scored,
  TeamMember? shooter,
});

/// Penalty / direct free hit in one window: team, kind, who shoots (if that
/// team is mine with a roster) and GOAL / MISSED.
class _SetPieceSheet extends ConsumerStatefulWidget {
  const _SetPieceSheet(
      {required this.view,
      required this.initialTeam,
      required this.initialKind,
      this.title});
  final MatchView view;
  final String? title;
  final TeamSide initialTeam;
  final String initialKind;

  @override
  ConsumerState<_SetPieceSheet> createState() => _SetPieceSheetState();
}

class _SetPieceSheetState extends ConsumerState<_SetPieceSheet> {
  late TeamSide _team = widget.initialTeam;
  late String _kind = widget.initialKind;
  TeamMember? _shooter;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final info = widget.view.info;
    final teamId = _team == TeamSide.home ? info.homeTeamId : info.awayTeamId;
    final players = teamId == null
        ? const <TeamMember>[]
        : ((ref.watch(teamMembersProvider(teamId)).valueOrNull ??
                const <TeamMember>[])
            .where((m) =>
                m.role == MemberRole.player || m.role == MemberRole.goalkeeper)
            .toList()
          ..sort((a, b) => (a.number ?? 999).compareTo(b.number ?? 999)));
    final color = teamColor(_team);
    void done(bool scored) => Navigator.pop<_SetPieceResult>(context, (
          team: _team,
          kind: _kind,
          scored: scored,
          shooter: _shooter,
        ));
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title ?? l.setPiece,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<TeamSide>(
                segments: [
                  ButtonSegment(
                      value: TeamSide.home,
                      label: Text(teamName(l, info, TeamSide.home),
                          overflow: TextOverflow.ellipsis)),
                  ButtonSegment(
                      value: TeamSide.away,
                      label: Text(teamName(l, info, TeamSide.away),
                          overflow: TextOverflow.ellipsis)),
                ],
                selected: {_team},
                onSelectionChanged: (v) => setState(() {
                  _team = v.first;
                  _shooter = null;
                }),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                      value: ShotKinds.penalty, label: Text(l.penalty)),
                  ButtonSegment(
                      value: ShotKinds.freeHit, label: Text(l.freeHit)),
                ],
                selected: {_kind},
                onSelectionChanged: (v) => setState(() => _kind = v.first),
              ),
              if (players.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(l.whoShot,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: PistakColors.textMuted)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in players)
                      ChoiceChip(
                        label: Text(m.label,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                        selected: _shooter?.id == m.id,
                        selectedColor: color.withValues(alpha: 0.3),
                        side: BorderSide(color: color, width: 1.5),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onSelected: (on) =>
                            setState(() => _shooter = on ? m : null),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 72,
                child: Row(children: [
                  Expanded(
                    child: EventButton(
                      label: l.shotScored,
                      icon: Icons.sports_hockey,
                      color: color,
                      filled: true,
                      onTap: () => done(true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: EventButton(
                      label: l.shotMissed,
                      icon: Icons.cancel_outlined,
                      color: color,
                      onTap: () => done(false),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Who {
  const _Who({this.side, this.player});
  final TeamSide? side;
  final TeamMember? player; // null = team only / no assist
}

/// "Who was it?": big player buttons of my linked team. Skippable.
class _WhoSheet extends ConsumerStatefulWidget {
  const _WhoSheet({
    required this.view,
    required this.title,
    this.side,
    this.chooseSide = false,
    this.exclude,
    this.noneLabel,
  });
  final MatchView view;
  final String title;
  final TeamSide? side;
  final bool chooseSide;
  final String? exclude;
  final String? noneLabel;

  @override
  ConsumerState<_WhoSheet> createState() => _WhoSheetState();
}

class _WhoSheetState extends ConsumerState<_WhoSheet> {
  late TeamSide? _side = widget.side ??
      (widget.view.info.homeTeamId != null ? TeamSide.home : TeamSide.away);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final info = widget.view.info;
    final teamId = switch (_side) {
      TeamSide.home => info.homeTeamId,
      TeamSide.away => info.awayTeamId,
      null => null,
    };
    final players = teamId == null
        ? const <TeamMember>[]
        : ((ref.watch(teamMembersProvider(teamId)).valueOrNull ??
                const <TeamMember>[])
            .where((m) =>
                (m.role == MemberRole.player ||
                    m.role == MemberRole.goalkeeper) &&
                m.id != widget.exclude)
            .toList()
          ..sort((a, b) => (a.number ?? 999).compareTo(b.number ?? 999)));
    final color = teamColor(_side);
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (widget.chooseSide) ...[
                SegmentedButton<TeamSide>(
                  segments: [
                    ButtonSegment(
                        value: TeamSide.home,
                        label: Text(teamName(l, info, TeamSide.home),
                            overflow: TextOverflow.ellipsis)),
                    ButtonSegment(
                        value: TeamSide.away,
                        label: Text(teamName(l, info, TeamSide.away),
                            overflow: TextOverflow.ellipsis)),
                  ],
                  selected: {_side ?? TeamSide.home},
                  onSelectionChanged: (v) => setState(() => _side = v.first),
                ),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in players)
                    SizedBox(
                      height: 56,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: color,
                          side: BorderSide(color: color, width: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        onPressed: () => Navigator.pop(
                            context, _Who(side: _side, player: m)),
                        child: Text(m.label,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l.skip),
                ),
                const Spacer(),
                if (widget.noneLabel != null)
                  FilledButton.tonal(
                    onPressed: () => Navigator.pop(context, _Who(side: _side)),
                    child: Text(widget.noneLabel!),
                  )
                else if (widget.chooseSide)
                  FilledButton.tonal(
                    onPressed: () => Navigator.pop(context, _Who(side: _side)),
                    child: Text(l.teamOnly),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 84),
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
          ),
        ),
      );
}
