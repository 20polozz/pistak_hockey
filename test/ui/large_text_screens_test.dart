// Accessibility: the other main screens must not overflow with large text.
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
import 'package:pistak/ui/screens/match_details_screen.dart';
import 'package:pistak/ui/screens/match_summary_screen.dart';
import 'package:pistak/ui/screens/onboarding_screen.dart';
import 'package:pistak/ui/screens/settings_screen.dart';
import 'package:pistak/ui/screens/stats_screen.dart';
import 'package:pistak/ui/screens/teams_screen.dart';
import 'package:pistak/ui/screens/timeline_screen.dart';

import 'real_fonts.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  // One in-memory DB per file (creating one per widget test made the test
  // process flaky on Windows).
  late AppDatabase db;
  setUpAll(() async {
    await loadRealFonts();
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDownAll(() => db.close());

  final screens = <String, Widget Function(String id)>{
    'home': (_) => const HomeScreen(),
    'summary': (id) => MatchSummaryScreen(matchId: id),
    'timeline': (id) => TimelineScreen(matchId: id),
    'details': (id) => MatchDetailsScreen(matchId: id),
    'settings': (_) => const SettingsScreen(),
    'teams': (_) => const TeamsScreen(),
    'onboarding': (_) => const OnboardingScreen(),
    'stats': (_) => const StatsScreen(),
  };

  for (final entry in screens.entries) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('${entry.key} at 360x640, text x$scale', (tester) async {
        final repo = DriftMatchRepository(db, deviceId: 'd');
        final m = await repo.createMatch(
            sport: rollerHockey.id,
            format: rollerHockey.defaultFormat,
            homeName: 'Club Patí Vilafranca de Bonany',
            awayName: 'Hoquei Club Sant Feliu de Codines',
            category: 'Sènior masculí',
            competition: 'Lliga Nacional Catalana');
        final c = MatchController(
            matchId: m.id,
            deviceId: 'd',
            repository: repo,
            clock: const SystemClock());
        await c.startMatch();
        await c.goal(TeamSide.home);
        await c.card(CardColors.blue, team: TeamSide.away);
        await c.incident(IncidentKinds.text,
            text: 'Discussió llarga a la banqueta visitant amb el delegat');
        await c.timeout(TeamSide.home);

        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final errors = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = errors.add;
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
            home: entry.value(m.id),
          ),
        ));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        FlutterError.onError = previous;
        expect(errors, isEmpty,
            reason: errors
                .map((d) => d.toString().split('\n').take(14).join('\n'))
                .join('\n---\n'));

        // Unmount; the in-memory DB is simply garbage-collected (closing it
        // while widget streams wind down made the test isolate flaky).
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      }, timeout: const Timeout(Duration(seconds: 60)));
    }
  }
}
