import 'dart:convert';

import '../core/clock.dart';
import '../domain/match/event_factory.dart';
import '../domain/match/match_event.dart';
import '../domain/match/match_state.dart';
import '../domain/repositories/match_repository.dart';
import '../ui/match_controller.dart';

/// One tap on the watch (see wear_os/…/Protocol.kt — same JSON).
class WearCommand {
  const WearCommand({
    required this.id,
    required this.cmd,
    required this.at,
    this.team,
    this.color,
  });

  final String id;
  final String cmd;
  final String? team;
  final String? color;
  final DateTime at;

  static WearCommand? tryParse(String json) {
    try {
      final o = jsonDecode(json) as Map<String, dynamic>;
      final id = o['id'] as String?;
      final cmd = o['cmd'] as String?;
      final at = o['at'] as int?;
      if (id == null || id.isEmpty || cmd == null || at == null) return null;
      return WearCommand(
        id: id,
        cmd: cmd,
        team: o['team'] as String?,
        color: o['color'] as String?,
        at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      );
    } on Object {
      return null; // malformed payload: ignored, never crashes the app
    }
  }

  TeamSide? get side => switch (team) {
        'home' => TeamSide.home,
        'away' => TeamSide.away,
        _ => null,
      };
}

enum WearOutcome { applied, duplicate, noActiveMatch, ignored }

/// Applies watch commands to the match in progress.
///
/// Idempotent: event ids are derived from the command id
/// ([MatchController.applyExternal]), so a command delivered twice (lost ack,
/// app restart while draining the inbox…) is stored once.
class WearCommandProcessor {
  WearCommandProcessor({
    required this.repository,
    required this.controllerFor,
    required this.clock,
  });

  final MatchRepository repository;
  final MatchController Function(String matchId) controllerFor;
  final Clock clock;

  Future<WearOutcome> process(WearCommand c) async {
    final match = await repository.watchActiveMatch().first;
    if (match == null) return WearOutcome.noActiveMatch;
    final ctl = controllerFor(match.id);
    // The tap time comes from the watch; never accept a moment in the future
    // (clock skew between devices).
    final now = clock.now();
    final at = c.at.isAfter(now) ? now : c.at;
    final team = c.side;

    List<MatchEvent> Function(EventFactory f, MatchState s) build;
    switch (c.cmd) {
      case 'goal' when team != null:
        build = (f, s) => f.goal(s, team);
      case 'foul' when team != null:
        build = (f, s) => f.foul(s, team);
      case 'timeout' when team != null:
        build = (f, s) => f.timeout(s, team);
      case 'card'
          when const {CardColors.yellow, CardColors.blue, CardColors.red}
              .contains(c.color):
        build = (f, s) => f.card(s, c.color!, team: team);
      case 'pause':
        build = (f, s) => f.pause(s);
      case 'resume':
        build =
            (f, s) => s.activeTimeout != null ? f.endTimeout(s) : f.resume(s);
      case 'incident':
        build = (f, s) => f.incident(s, kind: IncidentKinds.unjustified);
      default:
        return WearOutcome.ignored;
    }
    final events = await ctl.applyExternal(c.id, at, build);
    return events.isEmpty ? WearOutcome.duplicate : WearOutcome.applied;
  }
}

/// Scoreboard sent to the watch. The watch recomputes the running clock from
/// [matchMs] + elapsed since [atMs] (timestamps, not a ticking counter).
Map<String, Object?> wearScoreState(MatchState? s, DateTime now) {
  if (s == null) {
    return {
      'home': 0,
      'away': 0,
      'label': '—',
      'running': false,
      'matchMs': 0,
      'atMs': now.millisecondsSinceEpoch
    };
  }
  final label = s.isShootout
      ? 'PEN'
      : s.isOvertime
          ? 'PR${s.period - s.format.periods}'
          : s.isFinished
              ? 'FINAL'
              : 'P${s.period}';
  return {
    'home': s.home.goals,
    'away': s.away.goals,
    'label': label,
    'running': s.isClockRunning,
    'matchMs': s.matchTimeAt(now).inMilliseconds,
    'atMs': now.millisecondsSinceEpoch,
  };
}
