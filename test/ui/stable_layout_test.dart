import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/app/theme.dart';
import 'package:pistak/core/clock.dart';
import 'package:pistak/data/db/app_database.dart';
import 'package:pistak/data/repositories/drift_match_repository.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';
import 'package:pistak/l10n/app_localizations.dart';
import 'package:pistak/ui/match_controller.dart';
import 'package:pistak/ui/providers.dart';
import 'package:pistak/ui/screens/match_screen.dart';

import 'real_fonts.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  setUpAll(() async {
    await loadRealFonts();
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDownAll(() => db.close());

  for (final size in const [Size(412, 915), Size(360, 740)]) {
    testWidgets('cards never move the buttons (${size.width}x${size.height})',
        (tester) async {
      final repo = DriftMatchRepository(db, deviceId: 'd');
      final m = await repo.createMatch(
          sport: rollerHockey.id, format: rollerHockey.defaultFormat);
      await MatchController(
              matchId: m.id,
              deviceId: 'd',
              repository: repo,
              clock: const SystemClock())
          .startMatch();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          deviceIdProvider.overrideWithValue('d'),
        ],
        child: MaterialApp(
          theme: buildPistakTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MatchScreen(matchId: m.id),
        ),
      ));
      Future<void> settle() async {
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await settle();
      Rect goal() => tester.getRect(find.text('GOAL HOME'));
      Rect foul() => tester.getRect(find.text('FOUL AWAY'));
      final g0 = goal(), f0 = foul();

      // Yellow card without team: team buttons appear inside the bar.
      await tester.tap(find.byTooltip('YELLOW'));
      await settle();
      expect(goal(), g0);
      expect(foul(), f0);

      // Blue card for a team: exclusion countdown in the scoreboard.
      await tester.tap(find.byTooltip('BLUE'));
      await settle();
      await tester.tap(find.text('HOME').last);
      await settle();
      expect(goal(), g0);
      expect(foul(), f0);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }, timeout: const Timeout(Duration(seconds: 60)));
  }
}
