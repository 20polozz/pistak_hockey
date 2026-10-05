import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/sport_brand.dart';
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../widgets/brand.dart';
import 'home_screen.dart';

/// Welcome: sport image + "pistak." + EMPEZAR → straight to the app.
/// No account, no questions: everything is saved on the device.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: (box.maxHeight * 0.42).clamp(220.0, 420.0),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(currentBrand.heroAsset,
                            fit: BoxFit.cover,
                            alignment: Alignment.centerRight,
                            excludeFromSemantics: true),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0.5, 1.0],
                              colors: [
                                Color(0x000B0F14),
                                PistakColors.background
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Center(child: PistakWordmark(size: 64)),
                              const SizedBox(height: 4),
                              Text(l.sportName,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: currentBrand.accent,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 3,
                                      fontSize: 16)),
                              const SizedBox(height: 16),
                              Text(l.tagline,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(l.taglineSport,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: PistakColors.textMuted)),
                              const Spacer(),
                              const SizedBox(height: 24),
                              FilledButton(
                                onPressed: () => _start(context, ref),
                                child: Text(l.start),
                              ),
                              SizedBox(
                                  height: MediaQuery.paddingOf(context).bottom),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    await ref.read(settingsRepositoryProvider).setOnboardingDone();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()));
  }
}
