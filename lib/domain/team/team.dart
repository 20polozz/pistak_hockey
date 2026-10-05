import 'dart:typed_data';

import '../match/match_event.dart';

enum MemberRole {
  player,
  goalkeeper,
  coach,
  delegate;

  String get code => name;

  static MemberRole fromCode(String c) => MemberRole.values
      .firstWhere((r) => r.name == c, orElse: () => MemberRole.player);
}

/// A team managed by the user. Completely optional: matches never require
/// teams or players.
class Team {
  const Team({
    required this.id,
    required this.name,
    this.shortName,
    this.category,
    this.season,
    this.crest,
    required this.createdAt,
    required this.updatedAt,
    this.revision = 1,
    this.syncStatus = SyncStatus.pending,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String? shortName;
  final String? category;
  final String? season;

  /// Small PNG/JPEG of the crest (escut), optional.
  final Uint8List? crest;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
  final SyncStatus syncStatus;
  final DateTime? deletedAt;

  Team copyWith({
    String? name,
    String? shortName,
    String? category,
    String? season,
    Uint8List? crest,
    bool clearCrest = false,
  }) =>
      Team(
        id: id,
        name: name ?? this.name,
        shortName: shortName ?? this.shortName,
        category: category ?? this.category,
        season: season ?? this.season,
        crest: clearCrest ? null : (crest ?? this.crest),
        createdAt: createdAt,
        updatedAt: updatedAt,
        revision: revision,
        syncStatus: syncStatus,
        deletedAt: deletedAt,
      );
}

/// Player, goalkeeper, coach or delegate of a team.
class TeamMember {
  const TeamMember({
    required this.id,
    required this.teamId,
    required this.role,
    required this.name,
    this.number,
    this.position,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.revision = 1,
    this.syncStatus = SyncStatus.pending,
    this.deletedAt,
  });

  final String id;
  final String teamId;
  final MemberRole role;
  final String name;
  final int? number;
  final String? position;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
  final SyncStatus syncStatus;
  final DateTime? deletedAt;

  /// "#8 Joan" / "Joan".
  String get label => number == null ? name : '#$number $name';
}
