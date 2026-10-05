import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';

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
              ListTile(
                title: Text(l.deviceId),
                subtitle: SelectableText(ref.watch(deviceIdProvider)),
              ),
              ListTile(
                title: const Text('PISTAK'),
                subtitle: Text('${l.tagline}\n${l.savedLocally}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
