/// Event types are sport-agnostic strings. The team is a separate field
/// (`GOAL` + `team: home`) instead of `GOAL_HOME`, so new sports don't
/// multiply the number of types. See docs/ANALYSIS.md (C1).
abstract final class EventTypes {
  static const matchStart = 'MATCH_START';
  static const matchEnd = 'MATCH_END';
  static const periodStart = 'PERIOD_START';
  static const periodEnd = 'PERIOD_END';
  static const breakStart = 'BREAK_START';
  static const clockPause = 'CLOCK_PAUSE';
  static const clockResume = 'CLOCK_RESUME';
  static const clockAdjust = 'CLOCK_ADJUST';
  static const goal = 'GOAL';
  static const foul = 'FOUL';
  static const card = 'CARD';
  static const timeout = 'TIMEOUT';
  static const incident = 'INCIDENT';

  /// Events that change the clock / match phase.
  static const clockTypes = {
    matchStart,
    matchEnd,
    periodStart,
    periodEnd,
    breakStart,
    clockPause,
    clockResume,
    clockAdjust,
  };
}

abstract final class CardColors {
  static const yellow = 'yellow';
  static const blue = 'blue';
  static const red = 'red';
}

abstract final class IncidentKinds {
  static const text = 'text';
  static const voice = 'voice';
  static const unjustified = 'unjustified';
}

abstract final class PauseReasons {
  static const timeout = 'timeout';
}

/// Metadata keys used by the core.
abstract final class MetaKeys {
  static const text = 'text';
  static const periodElapsedMs = 'periodElapsedMs';
  static const forced = 'forced';
}

enum TeamSide {
  home,
  away;

  String get code => name;

  TeamSide get opponent => this == home ? away : home;

  static TeamSide? fromCode(String? code) => switch (code) {
        'home' => TeamSide.home,
        'away' => TeamSide.away,
        _ => null,
      };
}

enum SyncStatus {
  /// Saved locally, not yet confirmed by the server.
  pending,

  /// Confirmed by the server at the current revision.
  synced;

  String get code => name;

  static SyncStatus fromCode(String code) =>
      code == 'synced' ? SyncStatus.synced : SyncStatus.pending;
}

/// One immutable fact that happened during a match.
///
/// Never deleted: undo/delete sets [voidedAt] (tombstone) and edits bump
/// [revision]. The full history is always kept.
class MatchEvent {
  const MatchEvent({
    required this.id,
    required this.matchId,
    required this.type,
    this.subtype,
    this.team,
    required this.period,
    required this.matchTime,
    required this.periodTime,
    required this.timestamp,
    required this.createdAt,
    required this.updatedAt,
    required this.deviceId,
    required this.actionId,
    this.seq = 0,
    this.revision = 1,
    this.voidedAt,
    this.syncStatus = SyncStatus.pending,
    this.metadata = const {},
  });

  final String id;
  final String matchId;
  final String type;
  final String? subtype;
  final TeamSide? team;

  /// 1-based period number (0 = before the match started).
  final int period;

  /// Cumulative match time shown to the user (e.g. 43:21 in the 2nd half).
  final Duration matchTime;

  /// Time elapsed inside the current period.
  final Duration periodTime;

  /// Real wall-clock instant (UTC) when the event happened.
  final DateTime timestamp;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String deviceId;

  /// Groups events created by one user action (undo removes them together).
  final String actionId;

  /// Local insertion order inside the match (tie-breaker for ordering).
  final int seq;
  final int revision;
  final DateTime? voidedAt;
  final SyncStatus syncStatus;
  final Map<String, dynamic> metadata;

  bool get isVoided => voidedAt != null;

  String? get text => metadata[MetaKeys.text] as String?;

  MatchEvent copyWith({
    String? subtype,
    TeamSide? team,
    bool clearTeam = false,
    int? period,
    Duration? matchTime,
    Duration? periodTime,
    DateTime? updatedAt,
    int? seq,
    int? revision,
    DateTime? voidedAt,
    bool clearVoided = false,
    SyncStatus? syncStatus,
    Map<String, dynamic>? metadata,
  }) =>
      MatchEvent(
        id: id,
        matchId: matchId,
        type: type,
        subtype: subtype ?? this.subtype,
        team: clearTeam ? null : (team ?? this.team),
        period: period ?? this.period,
        matchTime: matchTime ?? this.matchTime,
        periodTime: periodTime ?? this.periodTime,
        timestamp: timestamp,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deviceId: deviceId,
        actionId: actionId,
        seq: seq ?? this.seq,
        revision: revision ?? this.revision,
        voidedAt: clearVoided ? null : (voidedAt ?? this.voidedAt),
        syncStatus: syncStatus ?? this.syncStatus,
        metadata: metadata ?? this.metadata,
      );

  /// Wire format (sync + JSON export).
  Map<String, dynamic> toJson() => {
        'id': id,
        'matchId': matchId,
        'type': type,
        'subtype': subtype,
        'team': team?.code,
        'period': period,
        'matchTimeMs': matchTime.inMilliseconds,
        'periodTimeMs': periodTime.inMilliseconds,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deviceId': deviceId,
        'actionId': actionId,
        'seq': seq,
        'revision': revision,
        'voidedAt': voidedAt?.toUtc().toIso8601String(),
        'metadata': metadata,
      };

  factory MatchEvent.fromJson(Map<String, dynamic> j) => MatchEvent(
        id: j['id'] as String,
        matchId: j['matchId'] as String,
        type: j['type'] as String,
        subtype: j['subtype'] as String?,
        team: TeamSide.fromCode(j['team'] as String?),
        period: (j['period'] as num).toInt(),
        matchTime: Duration(milliseconds: (j['matchTimeMs'] as num).toInt()),
        periodTime:
            Duration(milliseconds: (j['periodTimeMs'] as num?)?.toInt() ?? 0),
        timestamp: DateTime.parse(j['timestamp'] as String).toUtc(),
        createdAt: DateTime.parse(j['createdAt'] as String).toUtc(),
        updatedAt: DateTime.parse(j['updatedAt'] as String).toUtc(),
        deviceId: j['deviceId'] as String,
        actionId: j['actionId'] as String,
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        revision: (j['revision'] as num?)?.toInt() ?? 1,
        voidedAt: j['voidedAt'] == null
            ? null
            : DateTime.parse(j['voidedAt'] as String).toUtc(),
        metadata: Map<String, dynamic>.from(
            (j['metadata'] as Map?) ?? const <String, dynamic>{}),
      );

  @override
  String toString() =>
      'MatchEvent($type${subtype != null ? '/$subtype' : ''} ${team?.code ?? '-'} p$period ${matchTime.inSeconds}s seq=$seq${isVoided ? ' VOID' : ''})';
}

/// Chronological order: real timestamp, then local insertion order.
int compareEvents(MatchEvent a, MatchEvent b) {
  final c = a.timestamp.compareTo(b.timestamp);
  return c != 0 ? c : a.seq.compareTo(b.seq);
}
