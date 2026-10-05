import '../../core/clock.dart';
import '../../core/ids.dart';
import 'match_event.dart';
import 'match_state.dart';

/// What happens after the last regulation (or overtime) period ends.
enum PeriodEndChoice { endMatch, overtime, shootout }

/// Turns user commands into events, using the current [MatchState] to stamp
/// the exact match time and period.
///
/// Rules:
/// * Clock commands validate the transition and return an empty list when
///   they don't apply (e.g. pause while already paused).
/// * Recording commands (goal, foul, card, timeout, incident) are NEVER
///   rejected: losing a fact is worse than recording it at an odd moment.
/// * Every call returns the events of ONE user action (same [actionId]).
class EventFactory {
  EventFactory({
    required this.matchId,
    required this.deviceId,
    required this.clock,
    this.ids = const UuidV7Generator(),
  });

  final String matchId;
  final String deviceId;
  final Clock clock;
  final IdGenerator ids;

  /// Provisional local order; the repository assigns the definitive seq.
  int _seq = 0;

  // ---------------------------------------------------------------- clock

  List<MatchEvent> startMatch(MatchState s) {
    if (s.phase != MatchPhase.notStarted) return const [];
    final now = clock.now();
    final a = _Action(this, now);
    return [
      a.event(EventTypes.matchStart, period: 1, matchTime: Duration.zero),
      a.event(EventTypes.periodStart,
          period: 1,
          matchTime: Duration.zero,
          metadata: {MetaKeys.regularPeriods: s.format.periods}),
    ];
  }

  List<MatchEvent> pause(MatchState s) {
    if (s.phase != MatchPhase.running) return const [];
    final a = _Action(this, clock.now());
    return [a.eventAt(s, EventTypes.clockPause)];
  }

  List<MatchEvent> resume(MatchState s) {
    if (s.phase != MatchPhase.paused) return const [];
    final a = _Action(this, clock.now());
    return [a.eventAt(s, EventTypes.clockResume)];
  }

  /// Ends the current period.
  /// * More regulation periods left → break (Final 1a part → Descans).
  /// * Last regulation/overtime period → [then]: end of match, break before
  ///   overtime, or penalty shoot-out (only if the format allows it).
  List<MatchEvent> endPeriod(MatchState s,
      {PeriodEndChoice then = PeriodEndChoice.endMatch}) {
    if (!s.isInPlay) return const [];
    final a = _Action(this, clock.now());
    final end = a.eventAt(s, EventTypes.periodEnd,
        metadata: {MetaKeys.regularPeriods: s.format.periods});
    if (s.hasMoreRegularPeriods) {
      return [end, a.eventAt(s, EventTypes.breakStart)];
    }
    switch (then) {
      case PeriodEndChoice.overtime when s.canPlayOvertime:
        return [end, a.eventAt(s, EventTypes.breakStart)];
      case PeriodEndChoice.shootout when s.format.allowShootout:
        return [end, a.eventAt(s, EventTypes.shootoutStart)];
      default:
        return [end, a.eventAt(s, EventTypes.matchEnd)];
    }
  }

  /// Starts the penalty shoot-out from a break / ended period.
  List<MatchEvent> startShootout(MatchState s) {
    if (!s.format.allowShootout) return const [];
    if (s.phase != MatchPhase.onBreak && s.phase != MatchPhase.periodEnded) {
      return const [];
    }
    return [_Action(this, clock.now()).eventAt(s, EventTypes.shootoutStart)];
  }

  /// One penalty of the shoot-out (recording: never rejected).
  List<MatchEvent> shootoutAttempt(MatchState s, TeamSide team,
          {required bool scored}) =>
      [
        _Action(this, clock.now()).eventAt(s, EventTypes.shootoutAttempt,
            team: team,
            subtype: scored ? ShootoutResults.scored : ShootoutResults.missed),
      ];

  /// Starts the next period after a break.
  List<MatchEvent> startNextPeriod(MatchState s) {
    if (s.phase != MatchPhase.onBreak && s.phase != MatchPhase.periodEnded) {
      return const [];
    }
    if (!s.canPlayOvertime) return const [];
    final next = s.period + 1;
    final a = _Action(this, clock.now());
    return [
      a.event(
        EventTypes.periodStart,
        period: next,
        matchTime: s.format.startOf(next),
        metadata: {MetaKeys.regularPeriods: s.format.periods},
      ),
    ];
  }

  /// Ends the match at any moment (e.g. abandoned or shortened match).
  List<MatchEvent> endMatch(MatchState s) {
    if (s.phase == MatchPhase.finished) return const [];
    final a = _Action(this, clock.now());
    if (s.isInPlay) {
      return [
        a.eventAt(s, EventTypes.periodEnd,
            metadata: {MetaKeys.regularPeriods: s.format.periods}),
        a.eventAt(s, EventTypes.matchEnd, metadata: {MetaKeys.forced: true}),
      ];
    }
    return [
      a.eventAt(s, EventTypes.matchEnd, metadata: {MetaKeys.forced: true}),
    ];
  }

  /// Sets the elapsed time of the current period (align with the official
  /// scoreboard).
  List<MatchEvent> adjustClock(MatchState s, Duration periodElapsed) {
    if (s.period <= 0 || s.phase == MatchPhase.finished) return const [];
    if (periodElapsed.isNegative) return const [];
    final a = _Action(this, clock.now());
    return [
      a.event(
        EventTypes.clockAdjust,
        period: s.period,
        matchTime: s.format.startOf(s.period) + periodElapsed,
        periodTime: periodElapsed,
        metadata: {MetaKeys.periodElapsedMs: periodElapsed.inMilliseconds},
      ),
    ];
  }

  // ------------------------------------------------------------ recording

  List<MatchEvent> goal(MatchState s, TeamSide team) =>
      [_Action(this, clock.now()).eventAt(s, EventTypes.goal, team: team)];

  /// In-game penalty / direct free hit: a goal (counts in the score) or a
  /// missed shot. [kind] = ShotKinds.penalty | ShotKinds.freeHit.
  List<MatchEvent> setPiece(MatchState s, TeamSide team,
          {required String kind, required bool scored}) =>
      [
        _Action(this, clock.now()).eventAt(
            s, scored ? EventTypes.goal : EventTypes.shot,
            subtype: scored ? null : ShootoutResults.missed,
            team: team,
            metadata: {MetaKeys.shotKind: kind})
      ];

  List<MatchEvent> foul(MatchState s, TeamSide team) =>
      [_Action(this, clock.now()).eventAt(s, EventTypes.foul, team: team)];

  /// Card with optional team (one-tap registration; team can be set later).
  List<MatchEvent> card(MatchState s, String color, {TeamSide? team}) => [
        _Action(this, clock.now())
            .eventAt(s, EventTypes.card, subtype: color, team: team),
      ];

  /// Timeout. Pauses the clock too if the format says so and it runs.
  List<MatchEvent> timeout(MatchState s, TeamSide team) {
    final a = _Action(this, clock.now());
    final events = [a.eventAt(s, EventTypes.timeout, team: team)];
    if (s.phase == MatchPhase.running && s.format.stopClockOnTimeout) {
      events.add(
          a.eventAt(s, EventTypes.clockPause, subtype: PauseReasons.timeout));
    }
    return events;
  }

  /// Ends the active timeout. If the clock was stopped by it, the clock
  /// resumes in the same action (one tap = play restarts).
  List<MatchEvent> endTimeout(MatchState s) {
    final t = s.activeTimeout;
    if (t == null) return const [];
    final a = _Action(this, clock.now());
    final events = [a.eventAt(s, EventTypes.timeoutEnd, team: t.team)];
    if (s.phase == MatchPhase.paused) {
      events.add(a.eventAt(s, EventTypes.clockResume,
          subtype: ResumeReasons.timeoutEnd));
    }
    return events;
  }

  List<MatchEvent> incident(MatchState s,
      {String kind = IncidentKinds.unjustified,
      String? text,
      Map<String, dynamic> extra = const {}}) {
    final trimmed = text?.trim();
    return [
      _Action(this, clock.now()).eventAt(
        s,
        EventTypes.incident,
        subtype: kind,
        metadata: {
          if (trimmed != null && trimmed.isNotEmpty) MetaKeys.text: trimmed,
          ...extra,
        },
      ),
    ];
  }
}

/// Helper that stamps all events of one action with the same id and instant.
class _Action {
  _Action(this.f, this.now) : actionId = f.ids.newId();

  final EventFactory f;
  final DateTime now;
  final String actionId;

  /// Event stamped with the clock position of [s] at [now].
  MatchEvent eventAt(
    MatchState s,
    String type, {
    String? subtype,
    TeamSide? team,
    Map<String, dynamic> metadata = const {},
  }) =>
      event(
        type,
        subtype: subtype,
        team: team,
        period: s.period,
        matchTime: s.matchTimeAt(now),
        periodTime: s.periodElapsedAt(now),
        metadata: metadata,
      );

  MatchEvent event(
    String type, {
    String? subtype,
    TeamSide? team,
    required int period,
    required Duration matchTime,
    Duration periodTime = Duration.zero,
    Map<String, dynamic> metadata = const {},
  }) =>
      MatchEvent(
        id: f.ids.newId(),
        matchId: f.matchId,
        type: type,
        subtype: subtype,
        team: team,
        period: period,
        matchTime: matchTime,
        periodTime: periodTime,
        timestamp: now,
        createdAt: now,
        updatedAt: now,
        deviceId: f.deviceId,
        actionId: actionId,
        seq: ++f._seq,
        metadata: Map<String, dynamic>.of(metadata),
      );
}
