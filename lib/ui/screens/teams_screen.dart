import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../domain/team/team.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../widgets/pickers.dart';
import '../widgets/team_crest.dart';

String roleTitle(AppLocalizations l, MemberRole r) => switch (r) {
      MemberRole.player => l.rolePlayers,
      MemberRole.goalkeeper => l.roleGoalkeepers,
      MemberRole.coach => l.roleCoaches,
      MemberRole.delegate => l.roleDelegates,
    };

/// "Els meus equips": optional teams and rosters.
class TeamsScreen extends ConsumerWidget {
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final teams = ref.watch(teamsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.myTeams)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref, l),
        icon: const Icon(Icons.add),
        label: Text(l.newTeam),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Text(l.teamsOptionalHint,
                  style: const TextStyle(color: PistakColors.textMuted)),
              const SizedBox(height: 12),
              ...teams.when<List<Widget>>(
                loading: () => [const LinearProgressIndicator()],
                error: (e, _) => [Text('$e')],
                data: (list) => list.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(l.noTeams, textAlign: TextAlign.center),
                        )
                      ]
                    : [
                        for (final t in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Card(
                              child: ListTile(
                                leading: TeamCrest(team: t),
                                title: Text(t.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                subtitle: t.category == null && t.season == null
                                    ? null
                                    : Text([
                                        if (t.category != null) t.category!,
                                        if (t.season != null) t.season!,
                                      ].join(' · ')),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                        builder: (_) =>
                                            TeamDetailScreen(teamId: t.id))),
                              ),
                            ),
                          ),
                      ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create(
      BuildContext context, WidgetRef ref, AppLocalizations l) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: Text(l.newTeam),
          content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l.teamName),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, c.text),
                child: Text(l.save)),
          ],
        );
      },
    );
    if (name == null || name.trim().isEmpty) return;
    final team = await ref.read(teamRepositoryProvider).createTeam(name: name);
    if (context.mounted) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => TeamDetailScreen(teamId: team.id)));
    }
  }
}

class TeamDetailScreen extends ConsumerStatefulWidget {
  const TeamDetailScreen({super.key, required this.teamId});
  final String teamId;

  @override
  ConsumerState<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends ConsumerState<TeamDetailScreen> {
  Team? _team;
  final _name = TextEditingController();
  final _short = TextEditingController();
  final _category = TextEditingController();
  final _season = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await ref.read(teamRepositoryProvider).getTeam(widget.teamId);
    if (!mounted || t == null) return;
    setState(() {
      _team = t;
      _name.text = t.name;
      _short.text = t.shortName ?? '';
      _category.text = t.category ?? '';
      _season.text = t.season ?? '';
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _short, _category, _season]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final t = _team;
    if (t == null || _name.text.trim().isEmpty) return;
    await ref.read(teamRepositoryProvider).saveTeam(t.copyWith(
          name: _name.text,
          shortName: _short.text,
          category: _category.text,
          season: _season.text,
        ));
  }

  Future<void> _pickCrest() async {
    final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 256,
        maxHeight: 256,
        imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await ref.read(teamRepositoryProvider).setCrest(widget.teamId, bytes);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = _team;
    final members = ref.watch(teamMembersProvider(widget.teamId));
    return PopScope(
      onPopInvokedWithResult: (_, __) => _save(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(t?.name ?? ''),
          actions: [
            IconButton(
              tooltip: l.deleteTeam,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(l),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _editMember(l, null),
          icon: const Icon(Icons.person_add_alt),
          label: Text(l.addMember),
        ),
        body: t == null
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      Row(children: [
                        TeamCrest(team: t, size: 72),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Wrap(spacing: 8, runSpacing: 8, children: [
                            OutlinedButton.icon(
                              onPressed: _pickCrest,
                              icon: const Icon(Icons.image_outlined),
                              label: Text(l.pickCrest),
                            ),
                            if (t.crest != null)
                              TextButton(
                                onPressed: () async {
                                  await ref
                                      .read(teamRepositoryProvider)
                                      .setCrest(t.id, null);
                                  await _load();
                                },
                                child: Text(l.removeCrest),
                              ),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _field(_name, l.teamName),
                      _field(_short, l.teamShortName),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CategoryDropdown(
                          value: _category.text,
                          onChanged: (v) {
                            _category.text = v ?? '';
                            _save();
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SeasonDropdown(
                          value: _season.text,
                          onChanged: (v) {
                            _season.text = v ?? '';
                            _save();
                          },
                        ),
                      ),
                      ...members.when<List<Widget>>(
                        loading: () => [const LinearProgressIndicator()],
                        error: (e, _) => [Text('$e')],
                        data: (list) => [
                          for (final role in MemberRole.values)
                            ..._roleSection(l, role,
                                list.where((m) => m.role == role).toList()),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: label),
          onEditingComplete: _save,
        ),
      );

  List<Widget> _roleSection(
          AppLocalizations l, MemberRole role, List<TeamMember> list) =>
      [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Row(children: [
            Expanded(
              child: Text('${roleTitle(l, role)} (${list.length})',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            IconButton(
              tooltip: l.addMember,
              icon: const Icon(Icons.add),
              onPressed: () => _editMember(l, null, role: role),
            ),
          ]),
        ),
        if (list.isEmpty)
          Text(l.noMembers,
              style: const TextStyle(color: PistakColors.textMuted)),
        for (final m in list)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: PistakColors.surfaceHigh,
              child: Text(m.number?.toString() ?? '–',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            title: Text(m.name),
            subtitle: m.position == null ? null : Text(m.position!),
            onTap: () => _editMember(l, m),
          ),
      ];

  Future<void> _editMember(AppLocalizations l, TeamMember? m,
      {MemberRole role = MemberRole.player}) async {
    final result = await showDialog<_MemberResult>(
      context: context,
      builder: (_) => _MemberDialog(member: m, role: m?.role ?? role),
    );
    if (result == null) return;
    final repo = ref.read(teamRepositoryProvider);
    if (result.delete && m != null) {
      await repo.deleteMember(m.id);
    } else if (m == null) {
      await repo.addMember(widget.teamId,
          role: result.role,
          name: result.name,
          number: result.number,
          position: result.position,
          notes: result.notes);
    } else {
      await repo.saveMember(TeamMember(
        id: m.id,
        teamId: m.teamId,
        role: result.role,
        name: result.name,
        number: result.number,
        position: result.position,
        notes: result.notes,
        createdAt: m.createdAt,
        updatedAt: m.updatedAt,
      ));
    }
  }

  Future<void> _delete(AppLocalizations l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l.deleteTeamConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: PistakColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.deleteAction)),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(teamRepositoryProvider).deleteTeam(widget.teamId);
    if (mounted) Navigator.pop(context);
  }
}

class _MemberResult {
  const _MemberResult(
      this.role, this.name, this.number, this.position, this.notes,
      {this.delete = false});
  final MemberRole role;
  final String name;
  final int? number;
  final String? position;
  final String? notes;
  final bool delete;
}

class _MemberDialog extends StatefulWidget {
  const _MemberDialog({this.member, required this.role});
  final TeamMember? member;
  final MemberRole role;

  @override
  State<_MemberDialog> createState() => _MemberDialogState();
}

class _MemberDialogState extends State<_MemberDialog> {
  late MemberRole _role = widget.role;
  late final _name = TextEditingController(text: widget.member?.name ?? '');
  late final _number =
      TextEditingController(text: widget.member?.number?.toString() ?? '');
  late final _position =
      TextEditingController(text: widget.member?.position ?? '');
  late final _notes = TextEditingController(text: widget.member?.notes ?? '');

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hasNumber =
        _role == MemberRole.player || _role == MemberRole.goalkeeper;
    return AlertDialog(
      title: Text(roleTitle(l, _role)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<MemberRole>(
            initialValue: _role,
            decoration: InputDecoration(labelText: l.memberRole),
            items: [
              for (final r in MemberRole.values)
                DropdownMenuItem(value: r, child: Text(roleTitle(l, r))),
            ],
            onChanged: (r) => setState(() => _role = r ?? _role),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            autofocus: widget.member == null,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l.memberName),
          ),
          if (hasNumber) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _number,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.memberNumber),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _position,
              decoration: InputDecoration(labelText: l.memberPosition),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: InputDecoration(labelText: l.memberNotes),
          ),
        ]),
      ),
      actions: [
        if (widget.member != null)
          TextButton(
            onPressed: () => Navigator.pop(context,
                _MemberResult(_role, '', null, null, null, delete: true)),
            child: Text(l.deleteAction,
                style: const TextStyle(color: PistakColors.danger)),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _MemberResult(
                _role,
                _name.text,
                hasNumber ? int.tryParse(_number.text.trim()) : null,
                hasNumber ? _position.text : null,
                _notes.text,
              ),
            );
          },
          child: Text(l.save),
        ),
      ],
    );
  }
}
