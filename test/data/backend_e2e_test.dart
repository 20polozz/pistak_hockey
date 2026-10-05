// End-to-end: real PISTAK API process (backend/) + two app "devices" with
// their own local databases, HTTP sync, accounts, offline period.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/auth/remote_auth_service.dart';
import 'package:pistak/auth/token_store.dart';
import 'package:pistak/core/clock.dart';
import 'package:pistak/data/db/app_database.dart';
import 'package:pistak/data/repositories/drift_match_repository.dart';
import 'package:pistak/domain/match/match_event.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';
import 'package:pistak/sync/http_sync_api.dart';
import 'package:pistak/sync/sync_engine.dart';
import 'package:pistak/ui/match_controller.dart';

class Device {
  Device(this.name, this.baseUrl)
      : db = AppDatabase(NativeDatabase.memory()),
        clock = FakeClock(DateTime.utc(2026, 10, 12, 18)) {
    repo = DriftMatchRepository(db, deviceId: name, clock: clock);
    auth = RemoteAuthService(baseUrl: baseUrl, store: MemoryTokenStore());
  }
  final String name;
  String baseUrl;
  final AppDatabase db;
  final FakeClock clock;
  late final DriftMatchRepository repo;
  late final RemoteAuthService auth;
  int cursor = 0;

  SyncEngine engine() => SyncEngine(
        repository: repo,
        api: HttpSyncApi(baseUrl: baseUrl, token: auth.accessToken),
        auth: auth,
        readCursor: (_) async => cursor,
        writeCursor: (_, c) async => cursor = c,
      );
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  Process? server;
  late String url;
  late Directory tmp;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('pistak_e2e_');
    // Launch dart.exe directly (no shell) so kill() really stops the server.
    final root = Platform.environment['FLUTTER_ROOT'];
    final dartExe = root == null
        ? 'dart'
        : [root, 'bin', 'cache', 'dart-sdk', 'bin',
                Platform.isWindows ? 'dart.exe' : 'dart']
            .join(Platform.pathSeparator);
    server = await Process.start(
      dartExe,
      ['run', 'bin/server.dart'],
      workingDirectory: 'backend',
      runInShell: root == null,
      environment: {
        'PISTAK_EXIT_ON_STDIN_CLOSE': '1',
        'PISTAK_JWT_SECRET': 'e2e-secret-e2e-secret-e2e-secret-0123',
        'PISTAK_DB': '${tmp.path}${Platform.pathSeparator}e2e.sqlite',
        'PORT': '0',
      },
    );
    final ready = Completer<String>();
    server!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final m = RegExp(r'listening on :(\d+)').firstMatch(line);
      if (m != null && !ready.isCompleted) {
        ready.complete('http://127.0.0.1:${m.group(1)}');
      }
    });
    // ignore: avoid_print
    server!.stderr.transform(utf8.decoder).listen((e) => print('server: $e'));
    url = await ready.future.timeout(const Duration(seconds: 120));
  });

  tearDownAll(() async {
    await server?.stdin.close();
    server?.kill();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('offline match on phone → cloud → second device, edits both ways',
      () async {
    final phone = Device('phone', url);
    final tablet = Device('tablet', url);

    // Phone: create an account (needs network once).
    await phone.auth.register('coach@pistak.test', 'roller-hockey-2026');

    // Pavilion without coverage: the API is unreachable.
    phone.baseUrl = 'http://127.0.0.1:9';
    final m = await phone.repo.createMatch(
        sport: rollerHockey.id,
        format: rollerHockey.defaultFormat,
        homeName: 'CP Exemple',
        awayName: 'HC Exemple');
    final c = MatchController(
        matchId: m.id, deviceId: 'phone', repository: phone.repo, clock: phone.clock);
    await c.startMatch();
    for (var i = 0; i < 12; i++) {
      phone.clock.advance(const Duration(minutes: 1));
      await c.goal(i.isEven ? TeamSide.home : TeamSide.away);
    }
    final card = (await c.card(CardColors.blue)).single;
    await c.endMatch();
    final offline = await phone.engine().syncOnce();
    expect(offline.ok, isFalse, reason: 'no connection');
    expect((await phone.repo.pendingEvents(limit: 999)).length, 17);

    // Coverage is back: automatic sync.
    phone.baseUrl = url;
    final r1 = await phone.engine().syncOnce();
    expect(r1.ok, isTrue, reason: '${r1.error}');
    expect(r1.events, 17);
    expect(await phone.repo.pendingEvents(), isEmpty);
    // Sync again: nothing to send, nothing new.
    final r1b = await phone.engine().syncOnce();
    expect(r1b.events, 0);

    // Tablet: same account, empty device → gets everything.
    await tablet.auth.signIn('coach@pistak.test', 'roller-hockey-2026');
    final r2 = await tablet.engine().syncOnce();
    expect(r2.ok, isTrue, reason: '${r2.error}');
    final onTablet = (await tablet.repo.getMatch(m.id))!;
    expect(onTablet.homeName, 'CP Exemple');
    expect(onTablet.homeScore, 6);
    expect(onTablet.awayScore, 6);
    expect(onTablet.status.name, 'finished');
    expect((await tablet.repo.getEvents(m.id)).length, 17);

    // Tablet assigns the blue card to the away team → back to the phone.
    final tc = MatchController(
        matchId: m.id, deviceId: 'tablet', repository: tablet.repo, clock: tablet.clock);
    final onT = (await tablet.repo.getEvents(m.id)).firstWhere((e) => e.id == card.id);
    await tc.setTeam(onT, TeamSide.away);
    expect((await tablet.engine().syncOnce()).events, 1);
    final r3 = await phone.engine().syncOnce();
    expect(r3.ok, isTrue);
    final onPhone =
        (await phone.repo.getEvents(m.id)).firstWhere((e) => e.id == card.id);
    expect(onPhone.team, TeamSide.away);
    expect(onPhone.revision, 2);

    // Wrong password never gets in; another user never sees these matches.
    final intruder = Device('intruder', url);
    await expectLater(intruder.auth.signIn('coach@pistak.test', 'nope-nope'),
        throwsA(isA<AuthError>()));
    await intruder.auth.register('other@pistak.test', 'another-password');
    await intruder.engine().syncOnce();
    expect(await intruder.repo.getMatch(m.id), isNull);

    for (final d in [phone, tablet, intruder]) {
      await d.db.close();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
