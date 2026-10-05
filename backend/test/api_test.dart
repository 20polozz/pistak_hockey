import 'dart:convert';

import 'package:pistak_server/pistak_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late PistakApi api;
  late Handler h;

  setUp(() {
    api = PistakApi(
      store: SqliteStore(':memory:'),
      jwt: Jwt('test-secret-test-secret-test-secret-123'),
      hasher: PasswordHasher(iterations: 1000),
    );
    h = api.handler;
  });

  Future<(int, Map<String, dynamic>)> call(String method, String path,
      {Object? body, String? token}) async {
    final res = await h(Request(method, Uri.parse('http://x$path'),
        body: body == null ? null : jsonEncode(body),
        headers: {if (token != null) 'authorization': 'Bearer $token'}));
    final text = await res.readAsString();
    return (res.statusCode, text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>);
  }

  Future<String> register(String email) async {
    final (code, body) = await call('POST', '/auth/register',
        body: {'email': email, 'password': 'correct horse'});
    expect(code, 201);
    return body['token'] as String;
  }

  Map<String, dynamic> ev(String id, int rev) =>
      {'id': id, 'matchId': 'm1', 'type': 'GOAL', 'revision': rev};

  test('health', () async {
    expect((await call('GET', '/health')).$1, 200);
  });

  test('register / login / wrong password / duplicate', () async {
    await register('Ana@Example.com');
    expect((await call('POST', '/auth/register', body: {'email': 'ana@example.com', 'password': 'whatever1'})).$1, 409);
    expect((await call('POST', '/auth/login', body: {'email': 'ana@example.com', 'password': 'correct horse'})).$1, 200);
    expect((await call('POST', '/auth/login', body: {'email': 'ana@example.com', 'password': 'nope'})).$1, 401);
    expect((await call('POST', '/auth/register', body: {'email': 'x', 'password': 'whatever1'})).$1, 400);
    expect((await call('POST', '/auth/register', body: {'email': 'b@b.co', 'password': 'short'})).$1, 400);
  });

  test('passwords are never stored in plain text', () {
    final h = PasswordHasher(iterations: 1000);
    final stored = h.hash('secret-pass');
    expect(stored, isNot(contains('secret-pass')));
    expect(h.verify('secret-pass', stored), isTrue);
    expect(h.verify('Secret-pass', stored), isFalse);
  });

  test('brute force is throttled', () async {
    await register('c@c.co');
    for (var i = 0; i < 10; i++) {
      await call('POST', '/auth/login', body: {'email': 'c@c.co', 'password': 'bad$i'});
    }
    expect((await call('POST', '/auth/login', body: {'email': 'c@c.co', 'password': 'correct horse'})).$1, 429);
  });

  test('sync requires a valid token', () async {
    expect((await call('POST', '/sync/push', body: {})).$1, 401);
    expect((await call('GET', '/sync/pull', token: 'abc.def.ghi')).$1, 401);
  });

  test('push is idempotent and revision-aware', () async {
    final t = await register('d@d.co');
    var (code, body) = await call('POST', '/sync/push', token: t, body: {
      'matches': [{'id': 'm1', 'revision': 1}],
      'events': [ev('e1', 1), ev('e2', 1)],
    });
    expect(code, 200);
    expect(body['accepted']['events'], {'e1': 1, 'e2': 1});
    // Same batch again (lost ack): no duplicates.
    (code, body) = await call('POST', '/sync/push', token: t, body: {'events': [ev('e1', 1), ev('e2', 1)]});
    expect(api.store.count('event'), 2);
    // Edited event wins; an older revision never overwrites a newer one.
    await call('POST', '/sync/push', token: t, body: {'events': [ev('e1', 3)]});
    (code, body) = await call('POST', '/sync/push', token: t, body: {'events': [ev('e1', 2)]});
    expect(body['accepted']['events'], {'e1': 3});
  });

  test('pull returns only my changes, incrementally', () async {
    final a = await register('a@a.co');
    final b = await register('b@b.co');
    await call('POST', '/sync/push', token: a, body: {'matches': [{'id': 'ma', 'revision': 1}], 'events': [ev('ea', 1)]});
    await call('POST', '/sync/push', token: b, body: {'events': [ev('eb', 1)]});
    var (_, p) = await call('GET', '/sync/pull?since=0', token: a);
    expect((p['events'] as List).map((e) => e['id']), ['ea']);
    expect((p['matches'] as List).length, 1);
    final cursor = p['cursor'] as int;
    (_, p) = await call('GET', '/sync/pull?since=$cursor', token: a);
    expect(p['events'], isEmpty);
    await call('POST', '/sync/push', token: a, body: {'events': [ev('ea', 2)]});
    (_, p) = await call('GET', '/sync/pull?since=$cursor', token: a);
    expect((p['events'] as List).single['revision'], 2);
  });

  test('a user cannot overwrite another user\'s document', () async {
    final a = await register('a1@a.co');
    final b = await register('b1@b.co');
    await call('POST', '/sync/push', token: a, body: {'events': [ev('shared', 1)]});
    final (_, body) = await call('POST', '/sync/push', token: b, body: {'events': [ev('shared', 9)]});
    expect(body['rejected'], {'shared': 'forbidden'});
  });

  test('tokens expire and cannot be forged', () {
    final jwt = Jwt('test-secret-test-secret-test-secret-123', ttl: const Duration(minutes: 1));
    final t = jwt.issue('u1', now: DateTime.utc(2026, 1, 1));
    expect(jwt.verify(t, now: DateTime.utc(2026, 1, 1, 0, 0, 30)), 'u1');
    expect(jwt.verify(t, now: DateTime.utc(2026, 1, 1, 0, 2)), isNull);
    final other = Jwt('another-secret-another-secret-12345');
    expect(other.verify(t, now: DateTime.utc(2026, 1, 1)), isNull);
  });
}
