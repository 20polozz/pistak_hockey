import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/ids.dart';
import '../../domain/sport/match_format.dart';
import '../../domain/sport/sports.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';

/// Competition/category configuration: periods, durations, timeouts, rules.
/// Nothing about durations is hard-coded in the clock.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final custom = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.categories)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: Text(l.newCategory),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Text(l.categoriesHint,
                  style: const TextStyle(color: PistakColors.textMuted)),
              const SizedBox(height: 16),
              ...custom.when<List<Widget>>(
                loading: () => [const LinearProgressIndicator()],
                error: (e, _) => [Text('$e')],
                data: (list) => list.isEmpty
                    ? [Text(l.noCategories)]
                    : [
                        for (final f in list)
                          Card(
                            child: ListTile(
                              title: Text(f.name),
                              subtitle: Text(_describe(l, f)),
                              onTap: () => _edit(context, ref, f),
                              trailing: IconButton(
                                tooltip: l.deleteAction,
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  await ref
                                      .read(settingsRepositoryProvider)
                                      .deleteCategory(f.id);
                                  ref.invalidate(categoriesProvider);
                                },
                              ),
                            ),
                          ),
                      ],
              ),
              const SizedBox(height: 24),
              Text(l.builtInFormats,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final f in Sports.defaultSport.defaultFormats)
                ListTile(
                  title: Text(f.name),
                  subtitle: Text(_describe(l, f)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _describe(AppLocalizations l, MatchFormat f) =>
      '${l.formatPeriods}: ${f.periods} · ${f.periodDuration.inMinutes} min · '
      '${l.formatBreakMinutes}: ${f.breakDuration.inMinutes} · '
      '${l.formatTimeoutSeconds}: ${f.timeoutDuration.inSeconds}';

  Future<void> _edit(
      BuildContext context, WidgetRef ref, MatchFormat? existing) async {
    final result = await showDialog<MatchFormat>(
      context: context,
      builder: (_) => _CategoryDialog(existing: existing),
    );
    if (result == null) return;
    await ref.read(settingsRepositoryProvider).saveCategory(result);
    ref.invalidate(categoriesProvider);
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({this.existing});
  final MatchFormat? existing;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final MatchFormat base =
      widget.existing ?? Sports.defaultSport.defaultFormat;
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _periods = TextEditingController(text: '${base.periods}');
  late final _minutes =
      TextEditingController(text: '${base.periodDuration.inMinutes}');
  late final _break =
      TextEditingController(text: '${base.breakDuration.inMinutes}');
  late final _toSecs =
      TextEditingController(text: '${base.timeoutDuration.inSeconds}');
  late final _toPer =
      TextEditingController(text: '${base.timeoutsPerTeamPerPeriod}');
  late bool _stop = base.stopClockOnTimeout;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget num(TextEditingController c, String label) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label),
          ),
        );
    return AlertDialog(
      title: Text(widget.existing == null ? l.newCategory : l.edit),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: _name,
                autofocus: true,
                decoration:
                    InputDecoration(labelText: l.categoryName, errorText: _error),
              ),
            ),
            num(_periods, l.formatPeriods),
            num(_minutes, l.formatPeriodMinutes),
            num(_break, l.formatBreakMinutes),
            num(_toSecs, l.formatTimeoutSeconds),
            num(_toPer, l.formatTimeoutsPerPeriod),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.formatStopOnTimeout),
              value: _stop,
              onChanged: (v) => setState(() => _stop = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(onPressed: () => _save(l), child: Text(l.save)),
      ],
    );
  }

  void _save(AppLocalizations l) {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l.categoryName);
      return;
    }
    int read(TextEditingController c, int fallback, int min) {
      final v = int.tryParse(c.text.trim());
      return (v == null || v < min) ? fallback : v;
    }

    Navigator.pop(
      context,
      MatchFormat(
        id: widget.existing?.id ?? 'cat_${const UuidV7Generator().newId()}',
        name: name,
        periods: read(_periods, base.periods, 1),
        periodDuration:
            Duration(minutes: read(_minutes, base.periodDuration.inMinutes, 1)),
        breakDuration:
            Duration(minutes: read(_break, base.breakDuration.inMinutes, 0)),
        timeoutDuration:
            Duration(seconds: read(_toSecs, base.timeoutDuration.inSeconds, 1)),
        timeoutsPerTeamPerPeriod:
            read(_toPer, base.timeoutsPerTeamPerPeriod, 0),
        stopClockOnTimeout: _stop,
      ),
    );
  }
}
