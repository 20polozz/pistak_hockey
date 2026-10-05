import 'package:flutter/foundation.dart';

import 'storage_probe_stub.dart'
    if (dart.library.js_interop) 'storage_probe_web.dart' as probe;

/// Where the local database really lives. On the web the browser decides:
/// anything but [memory] survives a reload; [memory] means data would be
/// lost when the tab closes, so the UI warns loudly.
enum StorageKind { device, opfs, indexedDb, memory, unknown }

class StorageStatus {
  const StorageStatus(this.kind, {this.persisted});
  final StorageKind kind;

  /// Web: whether the browser granted persistent storage (won't evict it
  /// under storage pressure). null = unknown / not applicable.
  final bool? persisted;

  bool get isVolatile => kind == StorageKind.memory;
  bool get mayBeEvicted => kIsWeb && persisted == false;
}

final storageStatus = ValueNotifier<StorageStatus>(const StorageStatus(
    kIsWeb ? StorageKind.unknown : StorageKind.device,
    persisted: kIsWeb ? null : true));

/// Called by the web connection with drift's chosen implementation name.
void reportWebStorage(String implementationName) {
  final kind = switch (implementationName) {
    'opfsShared' || 'opfsLocks' => StorageKind.opfs,
    'sharedIndexedDb' || 'unsafeIndexedDb' => StorageKind.indexedDb,
    'inMemory' => StorageKind.memory,
    _ => StorageKind.unknown,
  };
  storageStatus.value =
      StorageStatus(kind, persisted: storageStatus.value.persisted);
}

/// Web: asks the browser to keep PISTAK's data even under storage pressure.
Future<void> requestPersistentStorage() async {
  if (!kIsWeb) return;
  final granted = await probe.requestPersist();
  storageStatus.value =
      StorageStatus(storageStatus.value.kind, persisted: granted);
}
