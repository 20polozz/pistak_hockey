// Accessibility: the match screen must stay usable with large system text
// on small phones (no overflow, main buttons reachable).
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/app/theme.dart';
import 'package:pistak/data/db/app_database.dart';
import 'package:pistak/data/repositories/drift_match_repository.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';
import 'package:pistak/l10n/app_localizations.dart';
import 'package:pistak/ui/match_controller.dart';
import 'package:pistak/core/clock.dart';
import 'package:pistak/ui/providers.dart';
import 'package:pistak/ui/screens/match_screen.dart';

import 'real_fonts.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(loadRealFonts);

  for (final (w, h) in [(360.0, 640.0), (412.0, 915.0)]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('match screen ${w.toInt()}x${h.toInt()} text x$scale',
          (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        late String id;
        {
          final repo = DriftMatchRepository(db, deviceId: 'd');
          final m = await repo.createMatch(
              sport: rollerHockey.id,
              format: rollerHockey.defaultFormat,
              homeName: 'Club Patí Vilafranca de Bonany',
              awayName: 'Hoquei Club Sant Feliu de Codines');
          id = m.id;
          await MatchController(
                  matchId: id,
                  deviceId: 'd',
                  repository: repo,
                  clock: const SystemClock())
              .startMatch();
        }
        tester.view.physicalSize = Size(w, h);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            deviceIdProvider.overrideWithValue('d'),
          ],
          child: MaterialApp(
            theme: buildPistakTheme(),
            locale: const Locale('ca'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: MatchScreen(matchId: id),
          ),
        ));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull,
            reason: 'no overflow / layout error');
        expect(find.textContaining('GOL'), findsWidgets);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        await db.close();
      }, timeout: const Timeout(Duration(seconds: 60)));
    }
  }
}
