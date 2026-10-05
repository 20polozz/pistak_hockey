import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'storage_status.dart';

/// Opens the platform database:
/// * Android: SQLite file in the app documents directory.
/// * Web: SQLite compiled to WASM, stored in OPFS when available (needs the
///   COOP/COEP headers, see docs/DEPLOYMENT.md) or IndexedDB otherwise.
///   Requires web/sqlite3.wasm and web/drift_worker.js (docs/SETUP.md).
QueryExecutor openConnection() => driftDatabase(
      name: 'pistak',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
        onResult: (result) {
          reportWebStorage(result.chosenImplementation.name);
          requestPersistentStorage();
        },
      ),
    );
