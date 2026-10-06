import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/app/theme.dart';
import 'package:pistak/data/db/app_database.dart';
import 'package:pistak/data/repositories/drift_match_repository.dart';
import 'package:pistak/data/repositories/drift_team_repository.dart';
import 'package:pistak/data/repositories/settings_repository.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';
import 'package:pistak/l10n/app_localizations.dart';
import 'package:pistak/ui/providers.dart';
import 'package:pistak/ui/screens/match_details_screen.dart';

import 'real_fonts.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  setUpAll(() async {
    await loadRealFonts();
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDownAll(() => db.close());

  testWidgets('linking my team fills category, edited durations and season',
      (tester) async {
    // The user edited the built-in "Aleví" to 2 × 22 in Settings.
    final alevi =
        rollerHockey.defaultFormats.firstWhere((f) => f.name == 'Aleví');
    await SettingsRepository(db).saveCategory(
        alevi.copyWith(periodDuration: const Duration(minutes: 22)));
    final team = await DriftTeamRepository(db)
        .createTeam(name: 'CP Vic', category: 'Aleví', season: '26/27');
    expect(team.category, 'Aleví');
    final repo = DriftMatchRepository(db, deviceId: 'd');
    final m = await repo.createMatch(
        sport: rollerHockey.id, format: rollerHockey.defaultFormat);

    tester.view.physicalSize = const Size(412, 1600);
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
        home: MatchDetailsScreen(matchId: m.id),
      ),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    await tester.tap(find.byIcon(Icons.groups_outlined).first);
    await settle();
    await tester.tap(find.text('CP Vic').last);
    await settle();
    await tester.tap(find.text('SAVE'));
    await settle();

    final saved = (await repo.getMatch(m.id))!;
    expect(saved.homeTeamId, team.id);
    expect(saved.category, 'Aleví');
    expect(saved.season, '26/27');
    expect(saved.format.periodDuration, const Duration(minutes: 22));
    expect(saved.format.periods, 2);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
