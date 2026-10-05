/// Timing rules of a match: number of periods, durations, timeouts...
///
/// A copy of the format is stored inside every match, so editing a category
/// later never changes matches that were already played.
class MatchFormat {
  const MatchFormat({
    required this.id,
    required this.name,
    required this.periods,
    required this.periodDuration,
    required this.breakDuration,
    this.timeoutsPerTeamPerPeriod = 1,
    this.timeoutDuration = const Duration(minutes: 1),
    this.stopClockOnTimeout = true,
  }) : assert(periods >= 1);

  final String id;
  final String name;
  final int periods;
  final Duration periodDuration;
  final Duration breakDuration;
  final int timeoutsPerTeamPerPeriod;
  final Duration timeoutDuration;

  /// If true, registering a timeout while the clock runs also pauses it.
  final bool stopClockOnTimeout;

  Duration get regulationDuration => periodDuration * periods;

  MatchFormat copyWith({
    String? id,
    String? name,
    int? periods,
    Duration? periodDuration,
    Duration? breakDuration,
    int? timeoutsPerTeamPerPeriod,
    Duration? timeoutDuration,
    bool? stopClockOnTimeout,
  }) =>
      MatchFormat(
        id: id ?? this.id,
        name: name ?? this.name,
        periods: periods ?? this.periods,
        periodDuration: periodDuration ?? this.periodDuration,
        breakDuration: breakDuration ?? this.breakDuration,
        timeoutsPerTeamPerPeriod:
            timeoutsPerTeamPerPeriod ?? this.timeoutsPerTeamPerPeriod,
        timeoutDuration: timeoutDuration ?? this.timeoutDuration,
        stopClockOnTimeout: stopClockOnTimeout ?? this.stopClockOnTimeout,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'periods': periods,
        'periodDurationMs': periodDuration.inMilliseconds,
        'breakDurationMs': breakDuration.inMilliseconds,
        'timeoutsPerTeamPerPeriod': timeoutsPerTeamPerPeriod,
        'timeoutDurationMs': timeoutDuration.inMilliseconds,
        'stopClockOnTimeout': stopClockOnTimeout,
      };

  factory MatchFormat.fromJson(Map<String, dynamic> j) => MatchFormat(
        id: j['id'] as String? ?? 'custom',
        name: j['name'] as String? ?? '',
        periods: (j['periods'] as num?)?.toInt() ?? 2,
        periodDuration:
            Duration(milliseconds: (j['periodDurationMs'] as num).toInt()),
        breakDuration: Duration(
            milliseconds: (j['breakDurationMs'] as num?)?.toInt() ?? 0),
        timeoutsPerTeamPerPeriod:
            (j['timeoutsPerTeamPerPeriod'] as num?)?.toInt() ?? 1,
        timeoutDuration: Duration(
            milliseconds: (j['timeoutDurationMs'] as num?)?.toInt() ?? 60000),
        stopClockOnTimeout: j['stopClockOnTimeout'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      other is MatchFormat &&
      other.id == id &&
      other.name == name &&
      other.periods == periods &&
      other.periodDuration == periodDuration &&
      other.breakDuration == breakDuration &&
      other.timeoutsPerTeamPerPeriod == timeoutsPerTeamPerPeriod &&
      other.timeoutDuration == timeoutDuration &&
      other.stopClockOnTimeout == stopClockOnTimeout;

  @override
  int get hashCode => Object.hash(id, name, periods, periodDuration,
      breakDuration, timeoutsPerTeamPerPeriod, timeoutDuration,
      stopClockOnTimeout);
}
