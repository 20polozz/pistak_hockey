import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Local SQLite database (native on Android, WASM on Web).
///
/// Schema changes MUST bump [schemaVersion] and add a migration step:
/// user data on devices is never thrown away.
@DriftDatabase(tables: [Matches, MatchEvents, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // Future migrations go here, e.g.
          // if (from < 2) await m.addColumn(matches, matches.someColumn);
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
