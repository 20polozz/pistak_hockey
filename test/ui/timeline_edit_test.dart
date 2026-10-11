import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/app/theme.dart';
import 'package:pistak/core/clock.dart';
import 'package:pistak/data/db/app_database.dart';
import 'package:pistak/data/repositories/drift_match_repository.dart';
import 'package:pistak/domain/match/event_clock.dart';
import 'package:pistak/domain/match/match_event.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';
import 'package:pistak/l10n/app_localizations.dart';
import 'package:pistak/ui/match_controller.dart';
import 'package:pistak/ui/providers.dart';
import 'package:pistak/ui/screens/timeline_screen.dart';

import 'real_fonts.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  setUpAll(() async {
    await loadRealFonts();
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDownAll(() => db.close());

  test('event times are shown like the scoreboard (time left)', () {
    final f = rollerHockey.defaultFormat; // 2×25
    expect(f.clockFor(1, const Duration(minutes: 3, seconds: 20)),
        const Duration(minutes: 21, seconds: 40));
    expect(f.clockFor(2, Duration.zero), const Duration(minutes: 25));
    expect(f.clockFor(1, const Duration(minutes: 27)), Duration.zero);
    expect(f.periodTimeForClock(1, const Duration(minutes: 21, seconds: 40)),
        const Duration(minutes: 3, seconds: 20));
  });

  testWidgets('timeline: countdown times, edit card colour and time',
      (tester) async {
    final repo = DriftMatchRepository(db, deviceId: 'd');
    final m = await repo.createMatch(
        sport: rollerHockey.id, format: rollerHockey.defaultFormat);
    final c = MatchController(
        matchId: m.id,
        deviceId: 'd',
        repository: repo,
        clock: const SystemClock());
    await c.startMatch();
    await c.card(CardColors.yellow, team: TeamSide.home);

    tester.view.physicalSize = const Size(412, 915);
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
        home: TimelineScreen(matchId: m.id),
      ),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    expect(find.textContaining('Tap an action'), findsOneWidget);
    expect(find.text('25:00'), findsWidgets, reason: 'countdown, not 00:00');
    expect(find.text('00:00'), findsNothing);

    await tester.tap(find.textContaining('Yellow card'));
    await settle();
    await tester.tap(find.text('BLUE'));
    await settle();
    await tester.enterText(find.byType(TextField).first, '20:30');
    await tester.tap(find.text('SAVE'));
    await settle();

    final card = (await repo.getEvents(m.id))
        .firstWhere((e) => e.type == EventTypes.card);
    expect(card.subtype, CardColors.blue);
    expect(card.periodTime, const Duration(minutes: 4, seconds: 30));
    expect(find.text('20:30'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
