import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/match/match_info.dart';
import '../../domain/sport/match_format.dart';
import '../../domain/sport/sports.dart';
import '../../l10n/app_localizations.dart';
import '../../domain/team/team.dart';
import '../providers.dart';
import '../widgets/pickers.dart';
import '../widgets/team_crest.dart';

/// Complete or edit the match information at any moment (before, during or
/// after the match). Never touches the events.
class MatchDetailsScreen extends ConsumerStatefulWidget {
  const MatchDetailsScreen(
      {super.key, required this.matchId, this.discardIfNotSaved = false});
  final String matchId;

  /// True for a match just created by "Programar partit": leaving without
  /// saving removes the empty draft instead of leaving junk in the list.
  final bool discardIfNotSaved;

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
  final _foulLimit = TextEditingController();
  final _shortTimeout = TextEditingController();
  final _foulEvery = TextEditingController();
  final _otPeriods = TextEditingController();
  bool _shootout = false;
  DateTime? _scheduledAt;
  String? _homeTeamId;
  String? _awayTeamId;
  late MatchFormat _format;
  bool _stopOnTimeout = true;
  bool _stopOnEvents = true;
  bool _saving = false;
  bool _saved = false;

  static const _customId = 'custom';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info =
        await ref.read(matchRepositoryProvider).getMatch(widget.matchId);
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
      _homeTeamId = info.homeTeamId;
      _awayTeamId = info.awayTeamId;
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
    _stopOnEvents = f.stopClockOnEvents;
    _foulLimit.text = '${f.foulLimit ?? 0}';
    _shortTimeout.text = '${f.shortTimeoutDuration?.inSeconds ?? 0}';
    _foulEvery.text = '${f.foulLimitEvery}';
    _otPeriods.text = '${f.overtimePeriods}';
    _shootout = f.allowShootout;
  }

  @override
  void dispose() {
    for (final c in [
      _home,
      _away,
      _category,
      _competition,
      _venue,
      _season,
      _notes,
      _periods,
      _minutes,
      _breakMinutes,
      _timeoutSeconds,
      _timeoutsPerPeriod,
      _foulLimit,
      _shortTimeout,
      _foulEvery,
      _otPeriods,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final info = _info;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && widget.discardIfNotSaved && !_saved) {
          ref.read(matchRepositoryProvider).deleteMatch(widget.matchId);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l.matchDetails)),
        body: info == null
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _teamField(l, home: true),
                      _teamField(l, home: false),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CategoryDropdown(
                          value: _category.text,
                          onChanged: (v) => setState(() {
                            _category.text = v ?? '';
                            final f = ref
                                .read(categoryCatalogProvider)
                                .valueOrNull
                                ?.byName(v);
                            if (f != null &&
                                _info?.status == MatchStatus.notStarted) {
                              _setFormat(f);
                            }
                          }),
                        ),
                      ),
                      _field(_competition, l.fieldCompetition),
                      _field(_venue, l.fieldVenue),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SeasonDropdown(
                          value: _season.text,
                          onChanged: (v) =>
                              setState(() => _season.text = v ?? ''),
                        ),
                      ),
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
      ),
    );
  }

  /// Free text name + optional link to one of "Els meus equips".
  Widget _teamField(AppLocalizations l, {required bool home}) {
    final ctrl = home ? _home : _away;
    final linkedId = home ? _homeTeamId : _awayTeamId;
    final teams = ref.watch(teamsProvider).valueOrNull ?? const <Team>[];
    Team? linked;
    for (final t in teams) {
      if (t.id == linkedId) linked = t;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) {
          // Editing the name by hand unlinks the team.
          if (linkedId != null && ctrl.text != linked?.name) {
            setState(() => home ? _homeTeamId = null : _awayTeamId = null);
          }
        },
        decoration: InputDecoration(
          labelText: home ? l.fieldHomeTeam : l.fieldAwayTeam,
          prefixIcon: linked == null
              ? null
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: TeamCrest(team: linked, size: 28)),
          suffixIcon: teams.isEmpty
              ? null
              : PopupMenuButton<String>(
                  tooltip: l.pickTeam,
                  icon: const Icon(Icons.groups_outlined),
                  onSelected: (id) => setState(() {
                    final t = teams.where((x) => x.id == id).firstOrNull;
                    if (home) {
                      _homeTeamId = t?.id;
                    } else {
                      _awayTeamId = t?.id;
                    }
                    if (t != null) {
                      ctrl.text = t.name;
                      _applyTeamDefaults(t);
                    }
                  }),
                  itemBuilder: (_) => [
                    PopupMenuItem<String>(value: '', child: Text(l.unlinkTeam)),
                    for (final t in teams)
                      PopupMenuItem<String>(value: t.id, child: Text(t.name)),
                  ],
                ),
        ),
      ),
    );
  }

  /// Linking one of my teams fills the match's category (and its durations)
  /// and season from the team, when they're still empty / not started.
  void _applyTeamDefaults(Team t) {
    final info = _info;
    if (info == null) return;
    if (_season.text.trim().isEmpty && (t.season?.trim().isNotEmpty ?? false)) {
      _season.text = t.season!.trim();
    }
    final cat =
        ref.read(categoryCatalogProvider).valueOrNull?.byName(t.category);
    if (cat == null || _category.text.trim().isNotEmpty) return;
    _category.text = cat.name;
    if (info.status == MatchStatus.notStarted) _setFormat(cat);
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
        subtitle:
            Text(d == null ? '—' : '${formatDate(d)}  ${formatClockTime(d)}'),
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

  /// "2 × 25'" / "4 × 8'".
  static String _formatShort(MatchFormat f) =>
      "${f.periods} × ${f.periodDuration.inMinutes}'";

  Widget _formatSection(AppLocalizations l, MatchInfo info) {
    final sport = Sports.byId(info.sport);
    final locked = info.status != MatchStatus.notStarted;
    final options = ref.watch(categoryCatalogProvider).valueOrNull?.all ??
        sport.defaultFormats;
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
            DropdownButtonFormField<String>(
              key: ValueKey('format:$selected:${options.length}'),
              initialValue: selected,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.fieldFormat),
              items: [
                for (final f in options)
                  DropdownMenuItem(
                    value: f.id,
                    child: Text('${f.name} · ${_formatShort(f)}',
                        overflow: TextOverflow.ellipsis),
                  ),
                DropdownMenuItem(value: _customId, child: Text(l.formatCustom)),
              ],
              onChanged: locked
                  ? null
                  : (id) => setState(() {
                        if (id == _customId) {
                          _format = _format.copyWith(
                              id: _customId, name: l.formatCustom);
                          return;
                        }
                        final f = options.firstWhere((o) => o.id == id);
                        // The category name follows the chosen preset unless
                        // the user typed a different one.
                        final typed = _category.text.trim();
                        if (typed.isEmpty ||
                            options.any((o) => o.name == typed)) {
                          _category.text = f.name;
                        }
                        _setFormat(f);
                      }),
            ),
            const SizedBox(height: 4),
            if (!isCustom)
              Text(_formatShort(_format),
                  style: const TextStyle(color: PistakColors.textMuted)),
            if (isCustom) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _numField(_periods, l.formatPeriods, locked)),
                const SizedBox(width: 8),
                Expanded(
                    child: _numField(_minutes, l.formatPeriodMinutes, locked)),
                const SizedBox(width: 8),
                Expanded(
                    child:
                        _numField(_breakMinutes, l.formatBreakMinutes, locked)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: _numField(
                        _timeoutSeconds, l.formatTimeoutSeconds, locked)),
                const SizedBox(width: 8),
                Expanded(
                    child: _numField(
                        _timeoutsPerPeriod, l.formatTimeoutsPerPeriod, locked)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: _numField(
                        _shortTimeout, l.formatShortTimeoutSeconds, locked)),
                const SizedBox(width: 8),
                Expanded(
                    child: _numField(_foulEvery, l.formatFoulEvery, locked)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: _numField(_foulLimit, l.formatFoulLimit, locked)),
                const SizedBox(width: 8),
                Expanded(
                    child:
                        _numField(_otPeriods, l.formatOvertimePeriods, locked)),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.formatAllowShootout),
                value: _shootout,
                onChanged: locked ? null : (v) => setState(() => _shootout = v),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.formatStopOnTimeout),
              value: _stopOnTimeout,
              onChanged:
                  locked ? null : (v) => setState(() => _stopOnTimeout = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.formatStopOnEvents),
              subtitle: Text(l.formatStopOnEventsHint),
              value: _stopOnEvents,
              onChanged:
                  locked ? null : (v) => setState(() => _stopOnEvents = v),
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
      return _format.copyWith(
          stopClockOnTimeout: _stopOnTimeout, stopClockOnEvents: _stopOnEvents);
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
    final foulLimit = read(_foulLimit, _format.foulLimit ?? 0, 0);
    final shortTo = read(_shortTimeout, 0, 0);
    final foulEvery = read(_foulEvery, _format.foulLimitEvery, 0);
    final otPeriods = read(_otPeriods, _format.overtimePeriods, 0);
    return _format.copyWith(
      id: _customId,
      name: '$periods × $minutes min',
      periods: periods,
      periodDuration: Duration(minutes: minutes),
      breakDuration: Duration(minutes: breakMin),
      timeoutDuration: Duration(seconds: toSecs),
      timeoutsPerTeamPerPeriod: toPer,
      shortTimeoutDuration: shortTo == 0 ? null : Duration(seconds: shortTo),
      clearShortTimeout: shortTo == 0,
      foulLimitEvery: foulEvery,
      stopClockOnTimeout: _stopOnTimeout,
      stopClockOnEvents: _stopOnEvents,
      foulLimit: foulLimit == 0 ? null : foulLimit,
      clearFoulLimit: foulLimit == 0,
      overtimePeriods: otPeriods,
      allowShootout: _shootout,
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
      homeTeamId: _homeTeamId,
      awayTeamId: _awayTeamId,
      clearHomeTeam: _homeTeamId == null,
      clearAwayTeam: _awayTeamId == null,
      awayName: _away.text,
      // Empty category + a preset format → the preset's name (filters/stats).
      category: _category.text.trim().isEmpty && format.id != _customId
          ? format.name
          : _category.text,
      competition: _competition.text,
      venue: _venue.text,
      season: _season.text,
      notes: _notes.text,
      scheduledAt: _scheduledAt,
      clearScheduledAt: _scheduledAt == null,
      format: format,
    );
    await ref.read(matchRepositoryProvider).saveMatchDetails(updated);
    _saved = true;
    if (!locked) {
      await ref.read(settingsRepositoryProvider).setLastFormat(format);
    }
    if (mounted) Navigator.pop(context);
  }
}
