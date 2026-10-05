import 'dart:typed_data';

import '../team/team.dart';

abstract class TeamRepository {
  Stream<List<Team>> watchTeams();
  Future<List<Team>> getTeams();
  Future<Team?> getTeam(String id);
  Future<Team> createTeam(
      {required String name, String? category, String? season});
  Future<void> saveTeam(Team team);
  Future<void> setCrest(String teamId, Uint8List? bytes);
  Future<void> deleteTeam(String id);

  Stream<List<TeamMember>> watchMembers(String teamId);
  Future<List<TeamMember>> getMembers(String teamId);
  Future<TeamMember> addMember(String teamId,
      {required MemberRole role,
      required String name,
      int? number,
      String? position,
      String? notes});
  Future<void> saveMember(TeamMember member);
  Future<void> deleteMember(String id);
}
