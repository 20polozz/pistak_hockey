import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Local SQLite database (native on Android, WASM on Web).
///
/// Schema changes MUST bump [schemaVersion] and add a migration step:
/// user data on devices is never thrown away.
@DriftDatabase(tables: [
  Matches,
  MatchEvents,
  AppSettings,
  AudioRecordings,
  Teams,
  TeamMembers,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // Never drop user data: only additive steps.
          if (from < 2) await m.createTable(audioRecordings);
          if (from < 3) {
            await m.createTable(teams);
            await m.createTable(teamMembers);
            await m.addColumn(matches, matches.homeTeamId);
            await m.addColumn(matches, matches.awayTeamId);
          }
        },
        beforeOpen: (details) async {
          // Durability first: every committed transaction is on disk.
          // WAL is not available on every web VFS, so failures are ignored.
          try {
            await customSelect('PRAGMA journal_mode = WAL').get();
          } catch (_) {}
          try {
            await customStatement('PRAGMA synchronous = FULL');
          } catch (_) {}
        },
      );
}
