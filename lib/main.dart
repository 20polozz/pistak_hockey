import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'auth/remote_auth_service.dart';
import 'auth/token_store.dart';
import 'data/db/app_database.dart';
import 'data/db/connection.dart';
import 'data/repositories/settings_repository.dart';
import 'ui/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final db = AppDatabase(openConnection());
    final settings = SettingsRepository(db);
    // Opening the DB + reading settings also validates local storage works
    // before the user can start recording.
    final deviceId = await settings.ensureDeviceId();
    final onboarded = await settings.isOnboardingDone();
    final locale = await settings.localeCode();

    // Optional cloud account (only when the build has a backend URL).
    RemoteAuthService? account;
    if (isBackendConfigured) {
      account = RemoteAuthService(
          baseUrl: apiBaseUrl, store: const SecureTokenStore());
      try {
        await account.load();
      } catch (_) {
        // A broken keystore must never block recording matches.
      }
    }

    runApp(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceIdProvider.overrideWithValue(deviceId),
        localeCodeProvider.overrideWith((ref) => locale),
        if (account != null) accountProvider.overrideWith((ref) => account),
      ],
      child: PistakApp(onboardingDone: onboarded),
    ));
  } catch (e) {
    runApp(_StorageErrorApp(error: e));
  }
}

/// Shown only if local storage can't be opened: recording without durable
/// storage would risk losing events, so we refuse instead.
class _StorageErrorApp extends StatelessWidget {
  const _StorageErrorApp({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'PISTAK\n\nLocal storage unavailable / Emmagatzematge local no disponible.\n\n$error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
