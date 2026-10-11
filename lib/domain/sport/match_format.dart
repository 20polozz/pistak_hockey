/// Timing rules of a match: periods, durations, timeouts, exclusions,
/// overtime and shoot-out.
///
/// A copy of the format is stored inside every match, so editing a category
/// later never changes matches that were already played. All the values are
/// configurable: nothing about a competition is hard-coded in the clock.
class MatchFormat {
  const MatchFormat({
    required this.id,
    required this.name,
    required this.periods,
    required this.periodDuration,
    required this.breakDuration,
    this.timeoutsPerTeamPerPeriod = 1,
    this.timeoutDuration = const Duration(minutes: 1),
    this.shortTimeoutDuration,
    this.stopClockOnTimeout = true,
    this.exclusionDuration = const Duration(minutes: 2),
    this.foulLimit,
    this.foulLimitEvery = 5,
    this.foulsResetEachPeriod = false,
    this.overtimePeriods = 0,
    this.overtimeDuration = const Duration(minutes: 5),
    this.allowShootout = false,
    this.stopClockOnEvents = false,
  }) : assert(periods >= 1);

  final String id;
  final String name;
  final int periods;
  final Duration periodDuration;
  final Duration breakDuration;
  final int timeoutsPerTeamPerPeriod;
  final Duration timeoutDuration;

  /// Roller hockey: of the timeouts of each period, one is shorter
  /// (1 min + 30 s). Null = all timeouts last [timeoutDuration].
  final Duration? shortTimeoutDuration;

  /// If true, registering a timeout while the clock runs also pauses it.
  final bool stopClockOnTimeout;

  /// Time a player is excluded after a blue card (counted as played time).
  final Duration exclusionDuration;

  /// Accumulated team fouls per period that trigger a sanction (e.g. a
  /// direct free hit). Null = no limit shown.
  final int? foulLimit;

  /// After [foulLimit], a new sanction every N more fouls (10, 15, 20…).
  /// 0 = only at the limit.
  final int foulLimitEvery;

  /// Team fouls start again from 0 each period. Roller hockey: false (they
  /// add up over the whole match: 10, then 15, 20…).
  final bool foulsResetEachPeriod;

  /// Extra periods available if the match must have a winner (0 = none).
  final int overtimePeriods;
  final Duration overtimeDuration;

  /// Whether a penalty shoot-out can be played after the last period.
  final bool allowShootout;

  /// Roller hockey "effective time": a goal, foul, card, penalty or direct
  /// free hit stops the running clock (in the same action, so undo restores
  /// it). Play restarts with RESUME.
  final bool stopClockOnEvents;

  /// Timeouts each team can take per period (e.g. [1:00, 0:30]).
  List<Duration> get timeoutSlots {
    final n = timeoutsPerTeamPerPeriod;
    if (n <= 0) return const [];
    final short = shortTimeoutDuration;
    if (short == null || short == timeoutDuration) {
      return List.filled(n, timeoutDuration);
    }
    return [...List.filled(n - 1, timeoutDuration), short];
  }

  /// The [n]-th team foul of a period gives a direct free hit.
  bool isFoulSanction(int n) {
    final limit = foulLimit;
    if (limit == null || n < limit) return false;
    if (foulLimitEvery <= 0) return n == limit;
    return (n - limit) % foulLimitEvery == 0;
  }

  /// Next foul count (>= [n]) that gives a direct free hit; null = none.
  int? nextFoulSanction(int n) {
    final limit = foulLimit;
    if (limit == null) return null;
    if (n <= limit) return limit;
    if (foulLimitEvery <= 0) return null;
    final steps = (n - limit + foulLimitEvery - 1) ~/ foulLimitEvery;
    return limit + steps * foulLimitEvery;
  }

  int get totalPeriods => periods + overtimePeriods;
  Duration get regulationDuration => periodDuration * periods;
  bool isOvertimePeriod(int n) => n > periods;

  /// Nominal length of period [n] (regulation or overtime).
  Duration durationOf(int n) =>
      isOvertimePeriod(n) ? overtimeDuration : periodDuration;

  /// Cumulative nominal match time at which period [n] starts.
  Duration startOf(int n) {
    if (n <= 1) return Duration.zero;
    final regular = n - 1 <= periods ? n - 1 : periods;
    final extra = n - 1 - regular;
    return periodDuration * regular + overtimeDuration * extra;
  }

  MatchFormat copyWith({
    String? id,
    String? name,
    int? periods,
    Duration? periodDuration,
    Duration? breakDuration,
    int? timeoutsPerTeamPerPeriod,
    Duration? timeoutDuration,
    Duration? shortTimeoutDuration,
    bool clearShortTimeout = false,
    bool? stopClockOnTimeout,
    Duration? exclusionDuration,
    int? foulLimit,
    bool clearFoulLimit = false,
    int? foulLimitEvery,
    bool? foulsResetEachPeriod,
    int? overtimePeriods,
    Duration? overtimeDuration,
    bool? allowShootout,
    bool? stopClockOnEvents,
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
        shortTimeoutDuration: clearShortTimeout
            ? null
            : (shortTimeoutDuration ?? this.shortTimeoutDuration),
        stopClockOnTimeout: stopClockOnTimeout ?? this.stopClockOnTimeout,
        exclusionDuration: exclusionDuration ?? this.exclusionDuration,
        foulLimit: clearFoulLimit ? null : (foulLimit ?? this.foulLimit),
        foulLimitEvery: foulLimitEvery ?? this.foulLimitEvery,
        foulsResetEachPeriod: foulsResetEachPeriod ?? this.foulsResetEachPeriod,
        overtimePeriods: overtimePeriods ?? this.overtimePeriods,
        overtimeDuration: overtimeDuration ?? this.overtimeDuration,
        allowShootout: allowShootout ?? this.allowShootout,
        stopClockOnEvents: stopClockOnEvents ?? this.stopClockOnEvents,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'periods': periods,
        'periodDurationMs': periodDuration.inMilliseconds,
        'breakDurationMs': breakDuration.inMilliseconds,
        'timeoutsPerTeamPerPeriod': timeoutsPerTeamPerPeriod,
        'timeoutDurationMs': timeoutDuration.inMilliseconds,
        'shortTimeoutDurationMs': shortTimeoutDuration?.inMilliseconds,
        'stopClockOnTimeout': stopClockOnTimeout,
        'exclusionDurationMs': exclusionDuration.inMilliseconds,
        'foulLimit': foulLimit,
        'foulLimitEvery': foulLimitEvery,
        'foulsResetEachPeriod': foulsResetEachPeriod,
        'overtimePeriods': overtimePeriods,
        'overtimeDurationMs': overtimeDuration.inMilliseconds,
        'allowShootout': allowShootout,
        'stopClockOnEvents': stopClockOnEvents,
      };

  /// Tolerant: formats saved by older versions lack the newer keys.
  factory MatchFormat.fromJson(Map<String, dynamic> j) {
    Duration ms(String k, int fallback) =>
        Duration(milliseconds: (j[k] as num?)?.toInt() ?? fallback);
    return MatchFormat(
      id: j['id'] as String? ?? 'custom',
      name: j['name'] as String? ?? '',
      periods: (j['periods'] as num?)?.toInt() ?? 2,
      periodDuration: ms('periodDurationMs', 25 * 60000),
      breakDuration: ms('breakDurationMs', 0),
      timeoutsPerTeamPerPeriod:
          (j['timeoutsPerTeamPerPeriod'] as num?)?.toInt() ?? 1,
      timeoutDuration: ms('timeoutDurationMs', 60000),
      shortTimeoutDuration: j['shortTimeoutDurationMs'] == null
          ? null
          : Duration(
              milliseconds: (j['shortTimeoutDurationMs'] as num).toInt()),
      stopClockOnTimeout: j['stopClockOnTimeout'] as bool? ?? true,
      exclusionDuration: ms('exclusionDurationMs', 120000),
      foulLimit: (j['foulLimit'] as num?)?.toInt(),
      foulLimitEvery: (j['foulLimitEvery'] as num?)?.toInt() ?? 5,
      foulsResetEachPeriod: j['foulsResetEachPeriod'] as bool? ?? false,
      overtimePeriods: (j['overtimePeriods'] as num?)?.toInt() ?? 0,
      overtimeDuration: ms('overtimeDurationMs', 5 * 60000),
      allowShootout: j['allowShootout'] as bool? ?? false,
      stopClockOnEvents: j['stopClockOnEvents'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MatchFormat && _eq(toJson(), other.toJson());

  static bool _eq(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(toJson().values);
}
