import 'package:drift/drift.dart';

// All instants are stored as INTEGER milliseconds since epoch (UTC) to keep
// full precision on every platform (drift's default DateTime mapping stores
// seconds).

@DataClassName('MatchRow')
@TableIndex(name: 'idx_matches_status', columns: {#status})
@TableIndex(name: 'idx_matches_sync', columns: {#syncStatus})
class Matches extends Table {
  TextColumn get id => text()();
  TextColumn get sport => text()();
  TextColumn get status => text()();

  /// JSON copy of the MatchFormat used by this match.
  TextColumn get formatJson => text()();

  TextColumn get homeName => text().nullable()();
  TextColumn get awayName => text().nullable()();

  /// Optional links to the user's teams (schema v3).
  TextColumn get homeTeamId => text().nullable()();
  TextColumn get awayTeamId => text().nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get competition => text().nullable()();
  TextColumn get venue => text().nullable()();
  TextColumn get season => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get scheduledAt => integer().nullable()();

  // Cache derived from the event log (recomputed in the same transaction).
  IntColumn get homeScore => integer().withDefault(const Constant(0))();
  IntColumn get awayScore => integer().withDefault(const Constant(0))();
  IntColumn get startedAt => integer().nullable()();
  IntColumn get endedAt => integer().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get deviceId => text()();
  TextColumn get ownerUserId => text().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MatchEventRow')
@TableIndex(name: 'idx_events_match_seq', columns: {#matchId, #seq})
@TableIndex(name: 'idx_events_sync', columns: {#syncStatus})
@TableIndex(name: 'idx_events_action', columns: {#actionId})
class MatchEvents extends Table {
  TextColumn get id => text()();
  TextColumn get matchId => text()();
  TextColumn get type => text()();
  TextColumn get subtype => text().nullable()();
  TextColumn get team => text().nullable()();
  IntColumn get period => integer()();
  IntColumn get matchTimeMs => integer()();
  IntColumn get periodTimeMs => integer()();

  /// Real instant when the event happened (domain: MatchEvent.timestamp).
  IntColumn get occurredAt => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get deviceId => text()();
  TextColumn get actionId => text()();
  IntColumn get seq => integer()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get voidedAt => integer().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  TextColumn get metadataJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SettingRow')
class AppSettings extends Table {
  TextColumn get settingKey => text()();
  TextColumn get settingValue => text()();

  @override
  Set<Column<Object>> get primaryKey => {settingKey};
}

/// Voice-incident audio. Bytes live in the database on every platform
/// (Android SQLite file / Web OPFS), so one code path handles both.
@DataClassName('AudioRow')
@TableIndex(name: 'idx_audio_match', columns: {#matchId})
@TableIndex(name: 'idx_audio_transcript', columns: {#transcriptStatus})
class AudioRecordings extends Table {
  TextColumn get id => text()();
  TextColumn get matchId => text()();
  TextColumn get eventId => text()();
  TextColumn get mimeType => text()();
  IntColumn get durationMs => integer()();
  IntColumn get sizeBytes => integer()();
  BlobColumn get bytes => blob().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get transcriptStatus =>
      text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TeamRow')
class Teams extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get shortName => text().nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get season => text().nullable()();
  BlobColumn get crest => blob().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TeamMemberRow')
@TableIndex(name: 'idx_members_team', columns: {#teamId})
class TeamMembers extends Table {
  TextColumn get id => text()();
  TextColumn get teamId => text()();
  TextColumn get role => text()();
  TextColumn get name => text()();
  IntColumn get number => integer().nullable()();
  TextColumn get position => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
