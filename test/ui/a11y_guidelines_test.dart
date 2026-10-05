// Accessibility guidelines (Flutter's checks used by Android/iOS audits):
// touch targets ≥ 48x48, every tappable thing has a label, readable contrast.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/app/theme.dart';
import 'package:pistak/core/clock.dart';
import 'package:pistak/data/db/app_database.dart';
import 'package:pistak/data/repositories/drift_match_repository.dart';
import 'package:pistak/domain/match/match_event.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';
import 'package:pistak/l10n/app_localizations.dart';
import 'package:pistak/ui/match_controller.dart';
import 'package:pistak/ui/providers.dart';
import 'package:pistak/ui/screens/home_screen.dart';
import 'package:pistak/ui/screens/match_screen.dart';
import 'package:pistak/ui/screens/match_summary_screen.dart';
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

  final screens = <String, Widget Function(String id)>{
    'match': (id) => MatchScreen(matchId: id),
    'home': (_) => const HomeScreen(),
    'summary': (id) => MatchSummaryScreen(matchId: id),
    'timeline': (id) => TimelineScreen(matchId: id),
  };

  for (final e in screens.entries) {
    testWidgets('${e.key} meets accessibility guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      final repo = DriftMatchRepository(db, deviceId: 'd');
      final m = await repo.createMatch(
          sport: rollerHockey.id,
          format: rollerHockey.defaultFormat,
          homeName: 'CP Vic',
          awayName: 'HC Liceo');
      final c = MatchController(
          matchId: m.id,
          deviceId: 'd',
          repository: repo,
          clock: const SystemClock());
      await c.startMatch();
      await c.goal(TeamSide.home);
      await c.card(CardColors.yellow, team: TeamSide.away);

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
          locale: const Locale('ca'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: e.value(m.id),
        ),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      handle.dispose();
    }, timeout: const Timeout(Duration(seconds: 60)));
  }
}
