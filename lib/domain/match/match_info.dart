import '../sport/match_format.dart';
import 'match_event.dart';

enum MatchStatus {
  notStarted,
  live,
  finished;

  String get code => switch (this) {
        MatchStatus.notStarted => 'not_started',
        MatchStatus.live => 'live',
        MatchStatus.finished => 'finished',
      };

  static MatchStatus fromCode(String code) => switch (code) {
        'live' => MatchStatus.live,
        'finished' => MatchStatus.finished,
        _ => MatchStatus.notStarted,
      };
}

/// Descriptive data of a match. Everything is optional except the id and
/// format: an "untitled match" can be started immediately and completed later.
///
/// Score/status/start/end are a cache derived from the event log (kept in
/// sync in the same DB transaction) so lists don't need to replay events.
class MatchInfo {
  const MatchInfo({
    required this.id,
    required this.sport,
    required this.format,
    this.status = MatchStatus.notStarted,
    this.homeName,
    this.awayName,
    this.homeTeamId,
    this.awayTeamId,
    this.category,
    this.competition,
    this.venue,
    this.season,
    this.notes,
    this.scheduledAt,
    this.homeScore = 0,
    this.awayScore = 0,
    this.startedAt,
    this.endedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.deviceId,
    this.ownerUserId,
    this.revision = 1,
    this.syncStatus = SyncStatus.pending,
    this.deletedAt,
  });

  final String id;
  final String sport;
  final MatchFormat format;
  final MatchStatus status;
  final String? homeName;
  final String? awayName;

  /// Optional links to the user's teams (names are still stored, so a match
  /// stays readable even if the team is deleted later).
  final String? homeTeamId;
  final String? awayTeamId;
  final String? category;
  final String? competition;
  final String? venue;
  final String? season;
  final String? notes;
  final DateTime? scheduledAt;
  final int homeScore;
  final int awayScore;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String deviceId;
  final String? ownerUserId;
  final int revision;
  final SyncStatus syncStatus;
  final DateTime? deletedAt;

  bool get isUntitled =>
      (homeName == null || homeName!.trim().isEmpty) &&
      (awayName == null || awayName!.trim().isEmpty);

  /// Best date to show for the match.
  DateTime get displayDate => startedAt ?? scheduledAt ?? createdAt;

  MatchInfo copyWith({
    MatchFormat? format,
    MatchStatus? status,
    String? homeName,
    String? awayName,
    String? homeTeamId,
    String? awayTeamId,
    bool clearHomeTeam = false,
    bool clearAwayTeam = false,
    String? category,
    String? competition,
    String? venue,
    String? season,
    String? notes,
    DateTime? scheduledAt,
    bool clearScheduledAt = false,
    int? homeScore,
    int? awayScore,
    DateTime? startedAt,
    DateTime? endedAt,
    DateTime? updatedAt,
    int? revision,
    SyncStatus? syncStatus,
    DateTime? deletedAt,
  }) =>
      MatchInfo(
        id: id,
        sport: sport,
        format: format ?? this.format,
        status: status ?? this.status,
        homeName: homeName ?? this.homeName,
        awayName: awayName ?? this.awayName,
        homeTeamId: clearHomeTeam ? null : (homeTeamId ?? this.homeTeamId),
        awayTeamId: clearAwayTeam ? null : (awayTeamId ?? this.awayTeamId),
        category: category ?? this.category,
        competition: competition ?? this.competition,
        venue: venue ?? this.venue,
        season: season ?? this.season,
        notes: notes ?? this.notes,
        scheduledAt:
            clearScheduledAt ? null : (scheduledAt ?? this.scheduledAt),
        homeScore: homeScore ?? this.homeScore,
        awayScore: awayScore ?? this.awayScore,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deviceId: deviceId,
        ownerUserId: ownerUserId,
        revision: revision ?? this.revision,
        syncStatus: syncStatus ?? this.syncStatus,
        deletedAt: deletedAt ?? this.deletedAt,
      );

  factory MatchInfo.fromJson(Map<String, dynamic> j) {
    DateTime? dt(String k) =>
        j[k] == null ? null : DateTime.parse(j[k] as String).toUtc();
    return MatchInfo(
      id: j['id'] as String,
      sport: j['sport'] as String? ?? 'roller_hockey',
      format: MatchFormat.fromJson(
          Map<String, dynamic>.from(j['format'] as Map? ?? const {})),
      status: MatchStatus.fromCode(j['status'] as String? ?? ''),
      homeName: j['homeName'] as String?,
      awayName: j['awayName'] as String?,
      homeTeamId: j['homeTeamId'] as String?,
      awayTeamId: j['awayTeamId'] as String?,
      category: j['category'] as String?,
      competition: j['competition'] as String?,
      venue: j['venue'] as String?,
      season: j['season'] as String?,
      notes: j['notes'] as String?,
      scheduledAt: dt('scheduledAt'),
      homeScore: (j['homeScore'] as num?)?.toInt() ?? 0,
      awayScore: (j['awayScore'] as num?)?.toInt() ?? 0,
      startedAt: dt('startedAt'),
      endedAt: dt('endedAt'),
      createdAt: dt('createdAt') ?? DateTime.now().toUtc(),
      updatedAt: dt('updatedAt') ?? DateTime.now().toUtc(),
      deviceId: j['deviceId'] as String? ?? 'remote',
      revision: (j['revision'] as num?)?.toInt() ?? 1,
      syncStatus: SyncStatus.synced,
      deletedAt: dt('deletedAt'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sport': sport,
        'format': format.toJson(),
        'status': status.code,
        'homeName': homeName,
        'awayName': awayName,
        'homeTeamId': homeTeamId,
        'awayTeamId': awayTeamId,
        'category': category,
        'competition': competition,
        'venue': venue,
        'season': season,
        'notes': notes,
        'scheduledAt': scheduledAt?.toUtc().toIso8601String(),
        'homeScore': homeScore,
        'awayScore': awayScore,
        'startedAt': startedAt?.toUtc().toIso8601String(),
        'endedAt': endedAt?.toUtc().toIso8601String(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deviceId': deviceId,
        'revision': revision,
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };
}
