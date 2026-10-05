import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../ui/providers.dart';
import '../ui/screens/home_screen.dart';
import '../ui/screens/onboarding_screen.dart';
import 'theme.dart';

class PistakApp extends ConsumerStatefulWidget {
  const PistakApp({super.key, required this.onboardingDone});

  final bool onboardingDone;

  @override
  ConsumerState<PistakApp> createState() => _PistakAppState();
}

class _PistakAppState extends ConsumerState<PistakApp> {
  Timer? _background;

  @override
  void initState() {
    super.initState();
    // Background work that never blocks recording: pending transcriptions
    // (and, from Phase 2, the cloud sync engine).
    _tick();
    ref.read(wearBridgeProvider).start();
    _background = Timer.periodic(const Duration(minutes: 2), (_) => _tick());
  }

  void _tick() {
    ref.read(transcriptionQueueProvider).processPending().ignore();
  }

  @override
  void dispose() {
    _background?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(syncAutoStartProvider);
    ref.listen(connectivityProvider, (_, next) {
      final online = next.valueOrNull?.any((c) => c != ConnectivityResult.none);
      if (online == true) ref.read(syncEngineProvider).poke();
    });
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
      home:
          widget.onboardingDone ? const HomeScreen() : const OnboardingScreen(),
    );
  }
}
