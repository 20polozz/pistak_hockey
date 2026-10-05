import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/data/db/storage_status.dart';
import 'package:pistak/l10n/app_localizations.dart';
import 'package:pistak/ui/widgets/storage_banner.dart';

void main() {
  test('drift implementation names map to storage kinds', () {
    reportWebStorage('opfsShared');
    expect(storageStatus.value.kind, StorageKind.opfs);
    reportWebStorage('unsafeIndexedDb');
    expect(storageStatus.value.kind, StorageKind.indexedDb);
    reportWebStorage('inMemory');
    expect(storageStatus.value.isVolatile, isTrue);
  });

  testWidgets('volatile storage shows a loud warning', (tester) async {
    storageStatus.value =
        const StorageStatus(StorageKind.opfs, persisted: true);
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        locale: Locale('ca'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            body: Column(children: [StorageBanner(), StorageInfoTile()])),
      ),
    ));
    expect(find.textContaining('PERDRÀ'), findsNothing);
    expect(find.textContaining('OPFS'), findsOneWidget);

    storageStatus.value = const StorageStatus(StorageKind.memory);
    await tester.pump();
    expect(find.textContaining('PERDRÀ'), findsOneWidget);
    expect(find.textContaining('només en memòria'), findsOneWidget);
  });
}
