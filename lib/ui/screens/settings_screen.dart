import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/sport_brand.dart';
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../widgets/backup_tiles.dart';
import '../widgets/brand.dart';
import '../widgets/storage_banner.dart';
import 'account_screen.dart';
import 'categories_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _languages = <(String, String)>[
    ('ca', 'Català'),
    ('es', 'Español'),
    ('en', 'English'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final current = ref.watch(localeCodeProvider);

    Future<void> select(String? code) async {
      ref.read(localeCodeProvider.notifier).state = code;
      await ref.read(settingsRepositoryProvider).setLocaleCode(code);
    }

    Widget option(String? code, String label) => ListTile(
          title: Text(label),
          leading: Icon(
            current == code
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: current == code ? PistakColors.accent : null,
          ),
          onTap: () => select(code),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            children: [
              ListTile(
                title: Text(l.language,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              option(null, l.languageSystem),
              for (final (code, name) in _languages) option(code, name),
              const Divider(),
              // Accounts only exist in builds with a backend (not the
              // shareable APK): everything is saved on the phone.
              if (isBackendConfigured)
                ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(l.account),
                  subtitle: Text(
                      ref.watch(accountProvider)?.email ?? l.syncLocalOnly),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const AccountScreen())),
                ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(l.categories),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const CategoriesScreen())),
              ),
              const Divider(),
              const BackupTiles(),
              const Divider(),
              const StorageInfoTile(),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PistakWordmark(size: 28),
                    const SizedBox(height: 4),
                    Text(l.sportName,
                        style: TextStyle(
                            color: currentBrand.accent,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            fontSize: 12)),
                    const SizedBox(height: 8),
                    Text(
                        l.appVersion(
                            ref.watch(appVersionProvider).valueOrNull ?? '…'),
                        style: const TextStyle(color: PistakColors.textMuted)),
                    Text('${l.tagline} ${l.savedLocally}',
                        style: const TextStyle(color: PistakColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
