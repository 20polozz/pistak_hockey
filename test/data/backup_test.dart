import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/core/clock.dart';
import 'package:pistak/data/db/app_database.dart';
import 'package:pistak/data/repositories/drift_audio_repository.dart';
import 'package:pistak/data/repositories/drift_match_repository.dart';
import 'package:pistak/data/repositories/drift_team_repository.dart';
import 'package:pistak/data/repositories/settings_repository.dart';
import 'package:pistak/domain/match/match_event.dart';
import 'package:pistak/domain/team/team.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';
import 'package:pistak/services/backup/backup_service.dart';
import 'package:pistak/ui/match_controller.dart';

class Phone {
  Phone(String id)
      : db = AppDatabase(NativeDatabase.memory()),
        clock = FakeClock(DateTime.utc(2026, 10, 12, 18)) {
    repo = DriftMatchRepository(db, deviceId: id, clock: clock);
    settings = SettingsRepository(db);
    teams = DriftTeamRepository(db, clock: clock);
    audio = DriftAudioRepository(db, clock: clock);
    backup = BackupService(
        db: db,
        matches: repo,
        settings: settings,
        clock: clock,
        iterations: 1000);
  }
  final AppDatabase db;
  final FakeClock clock;
  late final DriftMatchRepository repo;
  late final SettingsRepository settings;
  late final DriftTeamRepository teams;
  late final DriftAudioRepository audio;
  late final BackupService backup;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<(Phone, String, String)> filled() async {
    final p = Phone('old-phone');
    final team = await p.teams.createTeam(name: 'CP Vic', category: 'Sènior');
    await p.teams.setCrest(team.id, Uint8List.fromList([1, 2, 3, 4]));
    await p.teams
        .addMember(team.id, role: MemberRole.player, name: 'Marc', number: 7);
    final m = await p.repo.createMatch(
        sport: rollerHockey.id,
        format: rollerHockey.defaultFormat,
        homeName: 'CP Vic',
        awayName: 'HC Liceo');
    final c = MatchController(
        matchId: m.id,
        deviceId: 'old-phone',
        repository: p.repo,
        clock: p.clock,
        audio: p.audio);
    await c.startMatch();
    p.clock.advance(const Duration(minutes: 3));
    await c.goal(TeamSide.home);
    await c.goal(TeamSide.home);
    await c.card(CardColors.blue, team: TeamSide.away);
    final voice = (await c.voiceIncident(
            bytes: Uint8List.fromList(List.generate(3000, (i) => i % 256)),
            mimeType: 'audio/wav',
            duration: const Duration(seconds: 1),
            at: p.clock.now()))
        .single;
    await p.settings.set('categories', '[]');
    return (p, m.id, voice.metadata[MetaKeys.audioId] as String);
  }

  test('a new phone gets everything back from the backup', () async {
    final (old, matchId, audioId) = await filled();
    final file = await old.backup.export();

    final fresh = Phone('new-phone');
    final report = await fresh.backup.restore(file);
    expect(report.matches, 1);

    final info = (await fresh.repo.getMatch(matchId))!;
    expect(info.homeName, 'CP Vic');
    expect(info.homeScore, 2);
    expect((await fresh.repo.getEvents(matchId)).length,
        (await old.repo.getEvents(matchId)).length);
    final team = (await fresh.teams.getTeams()).single;
    expect(team.crest, [1, 2, 3, 4]);
    expect((await fresh.teams.getMembers(team.id)).single.number, 7);
    final rec = (await fresh.audio.get(audioId))!;
    expect(rec.bytes!.length, 3000);
    expect(await fresh.settings.get('categories'), '[]');

    // Restoring the same file again changes nothing (no duplicates).
    await fresh.backup.restore(file);
    expect((await fresh.repo.getEvents(matchId)).length,
        (await old.repo.getEvents(matchId)).length);
    expect((await fresh.teams.getTeams()).length, 1);
    expect((await fresh.repo.getMatch(matchId))!.homeScore, 2);
  });

  test('password-protected backup: encrypted, needs the right password',
      () async {
    final (old, matchId, _) = await filled();
    final file = await old.backup.export(password: 'patins-2026');
    expect(BackupService.isEncrypted(file), isTrue);
    expect(latin1.decode(file, allowInvalid: true), isNot(contains('CP Vic')),
        reason: 'nothing readable without the password');

    final fresh = Phone('new-phone');
    await expectLater(
        fresh.backup.restore(file), throwsA(isA<BackupPasswordRequired>()));
    await expectLater(fresh.backup.restore(file, password: 'wrong'),
        throwsA(isA<BackupWrongPassword>()));
    // A modified file is detected too.
    final tampered = Uint8List.fromList(file)..[file.length - 40] ^= 0xFF;
    await expectLater(fresh.backup.restore(tampered, password: 'patins-2026'),
        throwsA(isA<BackupWrongPassword>()));

    await fresh.backup.restore(file, password: 'patins-2026');
    expect((await fresh.repo.getMatch(matchId))!.homeScore, 2);
  });

  test('restoring never loses newer data on this phone', () async {
    final (old, matchId, _) = await filled();
    final file = await old.backup.export();
    // Same phone keeps recording after the backup was made…
    final c = MatchController(
        matchId: matchId,
        deviceId: 'old-phone',
        repository: old.repo,
        clock: old.clock);
    old.clock.advance(const Duration(minutes: 1));
    await c.goal(TeamSide.away);
    final before = (await old.repo.getEvents(matchId)).length;
    // …and then restores the older backup.
    await old.backup.restore(file);
    expect((await old.repo.getEvents(matchId)).length, before);
    expect((await old.repo.getMatch(matchId))!.awayScore, 1);
  });

  test('other files are rejected', () async {
    final p = Phone('x');
    await expectLater(p.backup.restore(Uint8List.fromList(utf8.encode('hola'))),
        throwsA(isA<BackupInvalid>()));
    await expectLater(
        p.backup
            .restore(Uint8List.fromList([0x50, 0x53, 0x54, 0x4B, 1, 0, 1, 2])),
        throwsA(isA<BackupInvalid>()));
  });
}
