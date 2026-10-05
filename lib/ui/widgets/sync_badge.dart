import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../sync/sync_engine.dart';
import '../providers.dart';

/// Discreet sync status. Informative only — it never blocks the user.
class SyncBadge extends ConsumerWidget {
  const SyncBadge({super.key, this.compact = false});

  /// Icon only (tooltip keeps the text) — for crowded app bars.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final auth = ref.watch(authServiceProvider);
    final pending = ref.watch(pendingCountProvider).valueOrNull ?? 0;
    final engine = ref.watch(syncEngineProvider);

    return StreamBuilder<SyncState>(
      stream: engine.states,
      initialData: engine.state,
      builder: (context, snap) {
        final state = auth.isSignedIn
            ? (snap.data ?? SyncState.idle)
            : SyncState.localOnly;
        final (color, icon, text) = switch (state) {
          SyncState.localOnly => (
              PistakColors.textMuted,
              Icons.smartphone,
              l.syncLocalOnly
            ),
          SyncState.idle => pending == 0
              ? (PistakColors.synced, Icons.cloud_done_outlined, l.syncSynced)
              : (
                  PistakColors.syncing,
                  Icons.cloud_upload_outlined,
                  l.pendingEvents(pending)
                ),
          SyncState.syncing => (
              PistakColors.syncing,
              Icons.sync,
              l.syncSyncing
            ),
          SyncState.offline => (
              PistakColors.offline,
              Icons.cloud_off_outlined,
              l.syncOffline
            ),
        };
        return Tooltip(
          message: text,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                if (!compact) ...[
                  const SizedBox(width: 4),
                  Text(text, style: TextStyle(fontSize: 12, color: color)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
