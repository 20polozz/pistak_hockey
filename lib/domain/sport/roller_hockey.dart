import '../match/match_event.dart';
import 'match_format.dart';
import 'sport_definition.dart';

/// Roller hockey (hoquei patins).
///
/// The presets below are editable starting points, not official rules:
/// each federation/category may differ, which is exactly why durations live
/// in [MatchFormat] and not in the clock.
const rollerHockey = SportDefinition(
  id: 'roller_hockey',
  supportedEventTypes: {
    EventTypes.matchStart,
    EventTypes.matchEnd,
    EventTypes.periodStart,
    EventTypes.periodEnd,
    EventTypes.breakStart,
    EventTypes.clockPause,
    EventTypes.clockResume,
    EventTypes.clockAdjust,
    EventTypes.goal,
    EventTypes.foul,
    EventTypes.card,
    EventTypes.timeout,
    EventTypes.timeoutEnd,
    EventTypes.incident,
  },
  cardColors: [CardColors.yellow, CardColors.blue, CardColors.red],
  defaultFormats: [
    MatchFormat(
      id: 'rh_2x25',
      name: '2 × 25 min',
      periods: 2,
      periodDuration: Duration(minutes: 25),
      breakDuration: Duration(minutes: 10),
      foulLimit: 10,
      overtimePeriods: 2,
      allowShootout: true,
    ),
    MatchFormat(
      id: 'rh_2x20',
      name: '2 × 20 min',
      periods: 2,
      periodDuration: Duration(minutes: 20),
      breakDuration: Duration(minutes: 10),
      foulLimit: 10,
      overtimePeriods: 2,
      allowShootout: true,
    ),
    MatchFormat(
      id: 'rh_2x15',
      name: '2 × 15 min',
      periods: 2,
      periodDuration: Duration(minutes: 15),
      breakDuration: Duration(minutes: 5),
      foulLimit: 10,
      overtimePeriods: 2,
      allowShootout: true,
    ),
  ],
);
