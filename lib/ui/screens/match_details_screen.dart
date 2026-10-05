import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/match/match_info.dart';
import '../../domain/sport/match_format.dart';
import '../../domain/sport/sports.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';

/// Complete or edit the match information at any moment (before, during or
/// after the match). Never touches the events.
class MatchDetailsScreen extends ConsumerStatefulWidget {
  const MatchDetailsScreen({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}

class _MatchDetailsScreenState extends ConsumerState<MatchDetailsScreen> {
  MatchInfo? _info;
  final _home = TextEditingController();
  final _away = TextEditingController();
  final _category = TextEditingController();
  final _competition = TextEditingController();
  final _venue = TextEditingController();
  final _season = TextEditingController();
  final _notes = TextEditingController();
  final _periods = TextEditingController();
  final _minutes = TextEditingController();
  final _breakMinutes = TextEditingController();
  final _timeoutSeconds = TextEditingController();
  final _timeoutsPerPeriod = TextEditingController();
  DateTime? _scheduledAt;
  late MatchFormat _format;
  bool _stopOnTimeout = true;
  bool _saving = false;

  static const _customId = 'custom';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await ref.read(matchRepositoryProvider).getMatch(widget.matchId);
    if (!mounted || info == null) return;
    setState(() {
      _info = info;
      _home.text = info.homeName ?? '';
      _away.text = info.awayName ?? '';
      _category.text = info.category ?? '';
      _competition.text = info.competition ?? '';
      _venue.text = info.venue ?? '';
      _season.text = info.season ?? '';
      _notes.text = info.notes ?? '';
      _scheduledAt = info.scheduledAt ?? info.startedAt;
      _setFormat(info.format);
    });
  }

  void _setFormat(MatchFormat f) {
    _format = f;
    _periods.text = '${f.periods}';
    _minutes.text = '${f.periodDuration.inMinutes}';
    _breakMinutes.text = '${f.breakDuration.inMinutes}';
    _timeoutSeconds.text = '${f.timeoutDuration.inSeconds}';
    _timeoutsPerPeriod.text = '${f.timeoutsPerTeamPerPeriod}';
    _stopOnTimeout = f.stopClockOnTimeout;
  }

  @override
  void dispose() {
    for (final c in [
      _home, _away, _category, _competition, _venue, _season, _notes,
      _periods, _minutes, _breakMinutes, _timeoutSeconds, _timeoutsPerPeriod,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final info = _info;
    return Scaffold(
      appBar: AppBar(title: Text(l.matchDetails)),
      body: info == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _field(_home, l.fieldHomeTeam),
                    _field(_away, l.fieldAwayTeam),
                    _field(_category, l.fieldCategory),
                    _field(_competition, l.fieldCompetition),
                    _field(_venue, l.fieldVenue),
                    _field(_season, l.fieldSeason),
                    _dateTile(l),
                    _field(_notes, l.fieldNotes, maxLines: 4),
                    const SizedBox(height: 8),
                    _formatSection(l, info),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : () => _save(l),
                      child: Text(l.save),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _field(TextEditingController c, String label, {int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          maxLines: maxLines,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label),
        ),
      );

  Widget _dateTile(AppLocalizations l) {
    final d = _scheduledAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        tileColor: PistakColors.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        leading: const Icon(Icons.event),
        title: Text(l.fieldDate),
        subtitle: Text(
            d == null ? '—' : '${formatDate(d)}  ${formatClockTime(d)}'),
        onTap: _pickDate,
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _scheduledAt?.toLocal() ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted) return;
    final t = time ?? TimeOfDay.fromDateTime(initial);
    setState(() => _scheduledAt =
        DateTime(date.year, date.month, date.day, t.hour, t.minute).toUtc());
  }

  Widget _formatSection(AppLocalizations l, MatchInfo info) {
    final sport = Sports.byId(info.sport);
    final locked = info.status != MatchStatus.notStarted;
    final options = [
      ...sport.defaultFormats,
      ...?ref.watch(categoriesProvider).valueOrNull,
    ];
    final presetIds = options.map((f) => f.id).toSet();
    final selected = presetIds.contains(_format.id) ? _format.id : _customId;
    final isCustom = selected == _customId;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.fieldFormat, style: Theme.of(context).textTheme.titleMedium),
            if (locked)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(l.formatLocked,
                    style: const TextStyle(color: PistakColors.textMuted)),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in options)
                  ChoiceChip(
                    label: Text(f.name),
                    selected: selected == f.id,
                    onSelected:
                        locked ? null : (_) => setState(() => _setFormat(f)),
                  ),
                ChoiceChip(
                  label: Text(l.formatCustom),
                  selected: isCustom,
                  onSelected: locked
                      ? null
                      : (_) => setState(() => _format =
                          _format.copyWith(id: _customId, name: l.formatCustom)),
                ),
              ],
            ),
            if (isCustom) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _numField(_periods, l.formatPeriods, locked)),
                const SizedBox(width: 8),
                Expanded(
                    child:
                        _numField(_minutes, l.formatPeriodMinutes, locked)),
                const SizedBox(width: 8),
                Expanded(
                    child: _numField(
                        _breakMinutes, l.formatBreakMinutes, locked)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: _numField(
                        _timeoutSeconds, l.formatTimeoutSeconds, locked)),
                const SizedBox(width: 8),
                Expanded(
                    child: _numField(_timeoutsPerPeriod,
                        l.formatTimeoutsPerPeriod, locked)),
              ]),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.formatStopOnTimeout),
              value: _stopOnTimeout,
              onChanged:
                  locked ? null : (v) => setState(() => _stopOnTimeout = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numField(TextEditingController c, String label, bool locked) =>
      TextField(
        controller: c,
        enabled: !locked,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
      );

  MatchFormat _resolvedFormat() {
    if (_format.id != _customId) {
      return _format.copyWith(stopClockOnTimeout: _stopOnTimeout);
    }
    int read(TextEditingController c, int fallback, int min) {
      final v = int.tryParse(c.text.trim());
      return (v == null || v < min) ? fallback : v;
    }

    final periods = read(_periods, _format.periods, 1);
    final minutes = read(_minutes, _format.periodDuration.inMinutes, 1);
    final breakMin = read(_breakMinutes, _format.breakDuration.inMinutes, 0);
    final toSecs = read(_timeoutSeconds, _format.timeoutDuration.inSeconds, 1);
    final toPer = read(_timeoutsPerPeriod, _format.timeoutsPerTeamPerPeriod, 0);
    return _format.copyWith(
      id: _customId,
      name: '$periods × $minutes min',
      periods: periods,
      periodDuration: Duration(minutes: minutes),
      breakDuration: Duration(minutes: breakMin),
      timeoutDuration: Duration(seconds: toSecs),
      timeoutsPerTeamPerPeriod: toPer,
      stopClockOnTimeout: _stopOnTimeout,
    );
  }

  Future<void> _save(AppLocalizations l) async {
    final info = _info;
    if (info == null) return;
    setState(() => _saving = true);
    final locked = info.status != MatchStatus.notStarted;
    final format = locked ? info.format : _resolvedFormat();
    final updated = info.copyWith(
      homeName: _home.text,
      awayName: _away.text,
      category: _category.text,
      competition: _competition.text,
      venue: _venue.text,
      season: _season.text,
      notes: _notes.text,
      scheduledAt: _scheduledAt,
      clearScheduledAt: _scheduledAt == null,
      format: format,
    );
    await ref.read(matchRepositoryProvider).saveMatchDetails(updated);
    if (!locked) {
      await ref.read(settingsRepositoryProvider).setLastFormat(format);
    }
    if (mounted) Navigator.pop(context);
  }
}
