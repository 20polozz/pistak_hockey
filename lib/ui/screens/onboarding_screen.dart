import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';
import 'home_screen.dart';

/// PISTAK → COMENÇAR → "Vols iniciar sessió?" → continue without account.
/// An account is never required to record a match.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _askLogin = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 2),
                  const Text(
                    'PISTAK',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8,
                        color: PistakColors.accent),
                  ),
                  const SizedBox(height: 8),
                  Text(l.tagline,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(l.taglineSport,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: PistakColors.textMuted)),
                  const Spacer(flex: 3),
                  if (!_askLogin)
                    FilledButton(
                      onPressed: () => setState(() => _askLogin = true),
                      child: Text(l.start),
                    )
                  else ...[
                    Text(l.loginQuestion,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(
                              SnackBar(content: Text(l.accountsComingSoon))),
                      child: Text(l.signIn),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _continue,
                      child: Text(l.continueWithoutAccount),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _continue() async {
    await ref.read(settingsRepositoryProvider).setOnboardingDone();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()));
  }
}
