import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../ui/providers.dart';
import '../ui/screens/home_screen.dart';
import '../ui/screens/onboarding_screen.dart';
import 'theme.dart';

class PistakApp extends ConsumerWidget {
  const PistakApp({super.key, required this.onboardingDone});

  final bool onboardingDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(localeCodeProvider);
    return MaterialApp(
      title: 'PISTAK',
      debugShowCheckedModeBanner: false,
      theme: buildPistakTheme(),
      darkTheme: buildPistakTheme(),
      themeMode: ThemeMode.dark,
      locale: code == null ? null : Locale(code),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Unknown device languages fall back to Catalan, PISTAK's home language.
      localeResolutionCallback: (device, supported) {
        if (device != null) {
          for (final l in supported) {
            if (l.languageCode == device.languageCode) return l;
          }
        }
        return const Locale('ca');
      },
      home: onboardingDone ? const HomeScreen() : const OnboardingScreen(),
    );
  }
}
