import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/match/match_event.dart';
import '../../domain/match/match_info.dart';
import '../../l10n/app_localizations.dart';

/// Human label of an event (localized, no hard-coded strings in widgets).
String eventLabel(AppLocalizations l, MatchEvent e) {
  switch (e.type) {
    case EventTypes.matchStart:
      return l.evMatchStart;
    case EventTypes.matchEnd:
      return l.evMatchEnd;
    case EventTypes.periodStart:
      return l.evPeriodStart(e.period);
    case EventTypes.periodEnd:
      return l.evPeriodEnd(e.period);
    case EventTypes.breakStart:
      return l.evBreak;
    case EventTypes.clockPause:
      return e.subtype == PauseReasons.timeout ? l.evPauseTimeout : l.evPause;
    case EventTypes.clockResume:
      return e.subtype == ResumeReasons.timeoutEnd
          ? l.evResumeAfterTimeout
          : l.evResume;
    case EventTypes.timeoutEnd:
      return l.evTimeoutEnd;
    case EventTypes.clockAdjust:
      return l.evClockAdjust;
    case EventTypes.goal:
      return l.evGoal;
    case EventTypes.foul:
      return l.evFoul;
    case EventTypes.card:
      return switch (e.subtype) {
        CardColors.yellow => l.evCardYellow,
        CardColors.blue => l.evCardBlue,
        CardColors.red => l.evCardRed,
        _ => l.evUnknown,
      };
    case EventTypes.timeout:
      return l.evTimeout;
    case EventTypes.incident:
      return switch (e.subtype) {
        IncidentKinds.voice => l.evIncidentVoice,
        IncidentKinds.unjustified => l.evIncidentUnjustified,
        _ => l.evIncident,
      };
    default:
      return l.evUnknown;
  }
}

String teamName(AppLocalizations l, MatchInfo info, TeamSide side) {
  final name = side == TeamSide.home ? info.homeName : info.awayName;
  if (name != null && name.trim().isNotEmpty) return name;
  return side == TeamSide.home ? l.home : l.away;
}

String matchTitle(AppLocalizations l, MatchInfo info) => info.isUntitled
    ? l.untitledMatch
    : '${teamName(l, info, TeamSide.home)} – ${teamName(l, info, TeamSide.away)}';

Color teamColor(TeamSide? side) => switch (side) {
      TeamSide.home => PistakColors.home,
      TeamSide.away => PistakColors.away,
      null => PistakColors.textMuted,
    };

Color cardColor(String? color) => switch (color) {
      CardColors.yellow => PistakColors.yellowCard,
      CardColors.blue => PistakColors.blueCard,
      CardColors.red => PistakColors.redCard,
      _ => PistakColors.textMuted,
    };

/// Accent colour + icon used for an event in lists.
(Color, IconData) eventVisual(MatchEvent e) {
  switch (e.type) {
    case EventTypes.goal:
      return (teamColor(e.team), Icons.sports_hockey);
    case EventTypes.foul:
      return (teamColor(e.team), Icons.front_hand);
    case EventTypes.card:
      return (cardColor(e.subtype), Icons.style);
    case EventTypes.timeout:
      return (teamColor(e.team), Icons.timer_outlined);
    case EventTypes.incident:
      return (
        PistakColors.incident,
        e.subtype == IncidentKinds.voice
            ? Icons.mic_none
            : Icons.report_problem_outlined
      );
    case EventTypes.timeoutEnd:
      return (teamColor(e.team), Icons.timer_off_outlined);
    case EventTypes.clockPause:
      return (PistakColors.textMuted, Icons.pause_circle_outline);
    case EventTypes.clockResume:
      return (PistakColors.textMuted, Icons.play_circle_outline);
    case EventTypes.clockAdjust:
      return (PistakColors.textMuted, Icons.tune);
    default:
      return (PistakColors.accent, Icons.flag_outlined);
  }
}

String statusLabel(AppLocalizations l, MatchStatus s) => switch (s) {
      MatchStatus.notStarted => l.statusNotStarted,
      MatchStatus.live => l.statusLive,
      MatchStatus.finished => l.statusFinished,
    };
