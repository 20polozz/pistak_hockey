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
    final catalog = ref.watch(categoryCatalogProvider);
    final settings = ref.read(settingsRepositoryProvider);
    Future<void> refresh() async => ref.invalidate(categoriesProvider);
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
          child: catalog.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (c) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Text(l.categoriesHint,
                    style: const TextStyle(color: PistakColors.textMuted)),
                const SizedBox(height: 12),
                for (final f in c.all)
                  Card(
                    child: ListTile(
                      title: Text(f.name),
                      subtitle: Text([
                        _describe(l, f),
                        if (c.isModified(f.id)) l.categoryModified,
                        if (!c.isBuiltIn(f.id)) l.categoryCustom,
                      ].join('\n')),
                      onTap: () => _edit(context, ref, f),
                      trailing: c.isModified(f.id)
                          ? IconButton(
                              tooltip: l.categoryRestore,
                              icon: const Icon(Icons.restore),
                              onPressed: () async {
                                await settings.deleteCategory(f.id);
                                await refresh();
                              },
                            )
                          : !c.isBuiltIn(f.id)
                              ? IconButton(
                                  tooltip: l.deleteAction,
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    await settings.deleteCategory(f.id);
                                    await refresh();
                                  },
                                )
                              : const Icon(Icons.edit_outlined),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _describe(AppLocalizations l, MatchFormat f) =>
      '${l.formatPeriods}: ${f.periods} · ${f.periodDuration.inMinutes} min · '
      '${l.formatBreakMinutes}: ${f.breakDuration.inMinutes} · '
      '${l.timeoutsShort}: ${f.timeoutSlots.map((d) => d.inSeconds < 60 ? '${d.inSeconds}"' : "${d.inMinutes}'").join(' + ')}';

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
  late final _toShort = TextEditingController(
      text: '${base.shortTimeoutDuration?.inSeconds ?? 0}');
  late final _foulEvery = TextEditingController(text: '${base.foulLimitEvery}');
  late final _excl =
      TextEditingController(text: '${base.exclusionDuration.inMinutes}');
  late final _foulLimit = TextEditingController(text: '${base.foulLimit ?? 0}');
  late final _otPeriods =
      TextEditingController(text: '${base.overtimePeriods}');
  late final _otMinutes =
      TextEditingController(text: '${base.overtimeDuration.inMinutes}');
  late bool _stop = base.stopClockOnTimeout;
  late bool _shootout = base.allowShootout;
  late bool _stopOnEvents = base.stopClockOnEvents;
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
                decoration: InputDecoration(
                    labelText: l.categoryName, errorText: _error),
              ),
            ),
            num(_periods, l.formatPeriods),
            num(_minutes, l.formatPeriodMinutes),
            num(_break, l.formatBreakMinutes),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.formatStopOnEvents),
              subtitle: Text(l.formatStopOnEventsHint),
              value: _stopOnEvents,
              onChanged: (v) => setState(() => _stopOnEvents = v),
            ),
            num(_toSecs, l.formatTimeoutSeconds),
            num(_toPer, l.formatTimeoutsPerPeriod),
            num(_toShort, l.formatShortTimeoutSeconds),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.formatStopOnTimeout),
              value: _stop,
              onChanged: (v) => setState(() => _stop = v),
            ),
            num(_excl, l.formatExclusionMinutes),
            num(_foulLimit, l.formatFoulLimit),
            num(_foulEvery, l.formatFoulEvery),
            num(_otPeriods, l.formatOvertimePeriods),
            num(_otMinutes, l.formatOvertimeMinutes),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.formatAllowShootout),
              value: _shootout,
              onChanged: (v) => setState(() => _shootout = v),
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
        shortTimeoutDuration: read(_toShort, 0, 0) == 0
            ? null
            : Duration(seconds: read(_toShort, 0, 0)),
        foulLimitEvery: read(_foulEvery, base.foulLimitEvery, 0),
        stopClockOnTimeout: _stop,
        exclusionDuration:
            Duration(minutes: read(_excl, base.exclusionDuration.inMinutes, 0)),
        foulLimit: read(_foulLimit, base.foulLimit ?? 0, 0) == 0
            ? null
            : read(_foulLimit, base.foulLimit ?? 0, 0),
        overtimePeriods: read(_otPeriods, base.overtimePeriods, 0),
        overtimeDuration: Duration(
            minutes: read(_otMinutes, base.overtimeDuration.inMinutes, 1)),
        allowShootout: _shootout,
        stopClockOnEvents: _stopOnEvents,
      ),
    );
  }
}
