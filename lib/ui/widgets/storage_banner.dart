import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/db/storage_status.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';

/// Loud warning when the browser can't keep data (would lose events), and a
/// softer one when it could evict it under storage pressure.
const _dismissKey = 'storage_hint_dismissed';

final _hintDismissedProvider = FutureProvider<bool>((ref) async =>
    await ref.watch(settingsRepositoryProvider).get(_dismissKey) == '1');

class StorageBanner extends ConsumerWidget {
  const StorageBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final signedIn = ref.watch(authServiceProvider).isSignedIn;
    final dismissed = ref.watch(_hintDismissedProvider).valueOrNull ?? true;
    return ValueListenableBuilder<StorageStatus>(
      valueListenable: storageStatus,
      builder: (context, s, _) {
        if (s.isVolatile) {
          return _box(
              PistakColors.danger, Icons.error_outline, l.storageVolatile,
              bold: true);
        }
        if (s.mayBeEvicted && !signedIn && !dismissed) {
          return _box(
              PistakColors.warning, Icons.info_outline, l.storageMayBeEvicted,
              onClose: () async {
            await ref.read(settingsRepositoryProvider).set(_dismissKey, '1');
            ref.invalidate(_hintDismissedProvider);
          }, closeLabel: MaterialLocalizations.of(context).closeButtonTooltip);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _box(Color color, IconData icon, String text,
          {bool bold = false, VoidCallback? onClose, String? closeLabel}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(text,
                      style: TextStyle(
                          fontWeight:
                              bold ? FontWeight.w800 : FontWeight.w500)),
                ),
                if (onClose != null)
                  IconButton(
                    tooltip: closeLabel,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: onClose,
                  ),
              ],
            ),
          ),
        ),
      );
}

/// Settings row: where the data lives and whether it's protected.
class StorageInfoTile extends StatelessWidget {
  const StorageInfoTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ValueListenableBuilder<StorageStatus>(
      valueListenable: storageStatus,
      builder: (context, s, _) {
        final where = switch (s.kind) {
          StorageKind.device => l.storageDevice,
          StorageKind.opfs => l.storageOpfs,
          StorageKind.indexedDb => l.storageIndexedDb,
          StorageKind.memory => l.storageMemory,
          StorageKind.unknown => l.storageUnknown,
        };
        final protected = switch (s.persisted) {
          true => l.storagePersistent,
          false => l.storageNotPersistent,
          null => null,
        };
        return ListTile(
          leading: Icon(Icons.storage_outlined,
              color: s.isVolatile ? PistakColors.danger : null),
          title: Text(l.storageSection),
          subtitle: Text([where, if (protected != null) protected].join('\n')),
        );
      },
    );
  }
}
