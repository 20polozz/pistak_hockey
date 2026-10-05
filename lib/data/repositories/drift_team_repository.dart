import 'package:drift/drift.dart';

import '../../core/clock.dart';
import '../../core/ids.dart';
import '../../domain/match/match_event.dart';
import '../../domain/repositories/team_repository.dart';
import '../../domain/team/team.dart';
import '../db/app_database.dart';

class DriftTeamRepository implements TeamRepository {
  DriftTeamRepository(this.db,
      {this.clock = const SystemClock(), this.ids = const UuidV7Generator()});

  final AppDatabase db;
  final Clock clock;
  final IdGenerator ids;

  int get _now => clock.now().millisecondsSinceEpoch;

  static String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  SimpleSelectStatement<$TeamsTable, TeamRow> _teams() => db.select(db.teams)
    ..where((t) => t.deletedAt.isNull())
    ..orderBy([(t) => OrderingTerm.asc(t.name)]);

  @override
  Stream<List<Team>> watchTeams() =>
      _teams().watch().map((r) => r.map(_team).toList());

  @override
  Future<List<Team>> getTeams() async =>
      (await _teams().get()).map(_team).toList();

  @override
  Future<Team?> getTeam(String id) async {
    final r = await (db.select(db.teams)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return r == null ? null : _team(r);
  }

  @override
  Future<Team> createTeam(
      {required String name, String? category, String? season}) async {
    final id = ids.newId();
    await db.into(db.teams).insert(TeamsCompanion(
          id: Value(id),
          name: Value(name.trim()),
          category: Value(_clean(category)),
          season: Value(_clean(season)),
          createdAt: Value(_now),
          updatedAt: Value(_now),
        ));
    return (await getTeam(id))!;
  }

  Future<void> _bump(String id, TeamsCompanion c) => db.transaction(() async {
        final cur = await (db.select(db.teams)..where((t) => t.id.equals(id)))
            .getSingle();
        await (db.update(db.teams)..where((t) => t.id.equals(id))).write(
            c.copyWith(
                updatedAt: Value(_now),
                revision: Value(cur.revision + 1),
                syncStatus: Value(SyncStatus.pending.code)));
      });

  @override
  Future<void> saveTeam(Team team) => _bump(
      team.id,
      TeamsCompanion(
        name: Value(team.name.trim()),
        shortName: Value(_clean(team.shortName)),
        category: Value(_clean(team.category)),
        season: Value(_clean(team.season)),
      ));

  @override
  Future<void> setCrest(String teamId, Uint8List? bytes) =>
      _bump(teamId, TeamsCompanion(crest: Value(bytes)));

  @override
  Future<void> deleteTeam(String id) =>
      _bump(id, TeamsCompanion(deletedAt: Value(_now)));

  // ---------------------------------------------------------------- members

  SimpleSelectStatement<$TeamMembersTable, TeamMemberRow> _members(
          String teamId) =>
      db.select(db.teamMembers)
        ..where((m) => m.teamId.equals(teamId) & m.deletedAt.isNull())
        ..orderBy([
          (m) => OrderingTerm.asc(m.role),
          (m) => OrderingTerm.asc(m.number, nulls: NullsOrder.last),
          (m) => OrderingTerm.asc(m.name),
        ]);

  @override
  Stream<List<TeamMember>> watchMembers(String teamId) =>
      _members(teamId).watch().map((r) => r.map(_member).toList());

  @override
  Future<List<TeamMember>> getMembers(String teamId) async =>
      (await _members(teamId).get()).map(_member).toList();

  @override
  Future<TeamMember> addMember(String teamId,
      {required MemberRole role,
      required String name,
      int? number,
      String? position,
      String? notes}) async {
    final id = ids.newId();
    await db.into(db.teamMembers).insert(TeamMembersCompanion(
          id: Value(id),
          teamId: Value(teamId),
          role: Value(role.code),
          name: Value(name.trim()),
          number: Value(number),
          position: Value(_clean(position)),
          notes: Value(_clean(notes)),
          createdAt: Value(_now),
          updatedAt: Value(_now),
        ));
    final r = await (db.select(db.teamMembers)..where((m) => m.id.equals(id)))
        .getSingle();
    return _member(r);
  }

  Future<void> _bumpMember(String id, TeamMembersCompanion c) =>
      db.transaction(() async {
        final cur = await (db.select(db.teamMembers)
              ..where((m) => m.id.equals(id)))
            .getSingle();
        await (db.update(db.teamMembers)..where((m) => m.id.equals(id))).write(
            c.copyWith(
                updatedAt: Value(_now),
                revision: Value(cur.revision + 1),
                syncStatus: Value(SyncStatus.pending.code)));
      });

  @override
  Future<void> saveMember(TeamMember m) => _bumpMember(
      m.id,
      TeamMembersCompanion(
        role: Value(m.role.code),
        name: Value(m.name.trim()),
        number: Value(m.number),
        position: Value(_clean(m.position)),
        notes: Value(_clean(m.notes)),
      ));

  @override
  Future<void> deleteMember(String id) =>
      _bumpMember(id, TeamMembersCompanion(deletedAt: Value(_now)));

  // ---------------------------------------------------------------- mapping

  static DateTime _dt(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

  static Team _team(TeamRow r) => Team(
        id: r.id,
        name: r.name,
        shortName: r.shortName,
        category: r.category,
        season: r.season,
        crest: r.crest,
        createdAt: _dt(r.createdAt),
        updatedAt: _dt(r.updatedAt),
        revision: r.revision,
        syncStatus: SyncStatus.fromCode(r.syncStatus),
        deletedAt: r.deletedAt == null ? null : _dt(r.deletedAt!),
      );

  static TeamMember _member(TeamMemberRow r) => TeamMember(
        id: r.id,
        teamId: r.teamId,
        role: MemberRole.fromCode(r.role),
        name: r.name,
        number: r.number,
        position: r.position,
        notes: r.notes,
        createdAt: _dt(r.createdAt),
        updatedAt: _dt(r.updatedAt),
        revision: r.revision,
        syncStatus: SyncStatus.fromCode(r.syncStatus),
        deletedAt: r.deletedAt == null ? null : _dt(r.deletedAt!),
      );
}
