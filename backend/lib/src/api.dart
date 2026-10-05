import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'security.dart';
import 'store.dart';

/// HTTP API:
///   GET  /health
///   POST /auth/register {email, password}      → {token, userId, email}
///   POST /auth/login    {email, password}      → {token, userId, email}
///   POST /sync/push     {matches:[], events:[]} (Bearer) → {accepted:{matches:{id:rev}, events:{id:rev}}, rejected:{id:reason}}
///   GET  /sync/pull?since=N                     (Bearer) → {matches:[], events:[], cursor}
class PistakApi {
  PistakApi({
    required this.store,
    required this.jwt,
    PasswordHasher? hasher,
    this.maxBatch = 500,
    this.allowedOrigins = const ['*'],
  }) : hasher = hasher ?? PasswordHasher();

  final Store store;
  final Jwt jwt;
  final PasswordHasher hasher;
  final int maxBatch;
  final List<String> allowedOrigins;
  final _failures = <String, List<DateTime>>{};
  final _rnd = Random.secure();

  Handler get handler => const Pipeline()
      .addMiddleware(_cors())
      .addMiddleware(_errors())
      .addHandler(_router.call);

  Router get _router => Router()
    ..get('/health', (Request r) => _json({'ok': true, 'service': 'pistak'}))
    ..post('/auth/register', _register)
    ..post('/auth/login', _login)
    ..post('/sync/push', _push)
    ..get('/sync/pull', _pull);

  // ------------------------------------------------------------------ auth

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<Response> _register(Request r) async {
    final body = await _body(r);
    final email = (body['email'] as String? ?? '').trim().toLowerCase();
    final password = body['password'] as String? ?? '';
    if (!_emailRe.hasMatch(email) || email.length > 254) {
      return _json({'error': 'invalid_email'}, 400);
    }
    if (password.length < 8 || password.length > 200) {
      return _json({'error': 'weak_password'}, 400);
    }
    if (store.userByEmail(email) != null) {
      return _json({'error': 'email_taken'}, 409);
    }
    final user = store.createUser(_newId(), email, hasher.hash(password));
    return _json({'token': jwt.issue(user.id), 'userId': user.id, 'email': user.email}, 201);
  }

  Future<Response> _login(Request r) async {
    final body = await _body(r);
    final email = (body['email'] as String? ?? '').trim().toLowerCase();
    final password = body['password'] as String? ?? '';
    if (_tooManyFailures(email)) return _json({'error': 'too_many_attempts'}, 429);
    final user = store.userByEmail(email);
    if (user == null || !hasher.verify(password, user.passwordHash)) {
      (_failures[email] ??= []).add(DateTime.now());
      return _json({'error': 'invalid_credentials'}, 401);
    }
    _failures.remove(email);
    return _json({'token': jwt.issue(user.id), 'userId': user.id, 'email': user.email});
  }

  bool _tooManyFailures(String email) {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 15));
    final list = (_failures[email] ?? [])..removeWhere((t) => t.isBefore(cutoff));
    return list.length >= 10;
  }

  String? _user(Request r) {
    final h = r.headers['authorization'] ?? '';
    if (!h.startsWith('Bearer ')) return null;
    return jwt.verify(h.substring(7));
  }

  // ------------------------------------------------------------------ sync

  Future<Response> _push(Request r) async {
    final uid = _user(r);
    if (uid == null) return _json({'error': 'unauthorized'}, 401);
    final body = await _body(r);
    final matches = (body['matches'] as List?) ?? const [];
    final events = (body['events'] as List?) ?? const [];
    if (matches.length + events.length > maxBatch) {
      return _json({'error': 'batch_too_large', 'max': maxBatch}, 413);
    }
    final accM = <String, int>{};
    final accE = <String, int>{};
    final rejected = <String, String>{};
    void apply(String kind, List<dynamic> docs, Map<String, int> acc) {
      for (final d in docs) {
        if (d is! Map<String, dynamic>) continue;
        final res = store.upsert(kind, uid, d);
        final id = d['id'] as String? ?? '?';
        if (res.revision != null) {
          acc[id] = res.revision!;
        } else {
          rejected[id] = res.rejected!;
        }
      }
    }

    apply('match', matches, accM);
    apply('event', events, accE);
    return _json({
      'accepted': {'matches': accM, 'events': accE},
      'rejected': rejected,
    });
  }

  Future<Response> _pull(Request r) async {
    final uid = _user(r);
    if (uid == null) return _json({'error': 'unauthorized'}, 401);
    final since = int.tryParse(r.url.queryParameters['since'] ?? '0') ?? 0;
    final c = store.changesSince(uid, since);
    return _json({'matches': c.matches, 'events': c.events, 'cursor': c.cursor});
  }

  // --------------------------------------------------------------- helpers

  String _newId() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static Future<Map<String, dynamic>> _body(Request r) async {
    final text = await r.readAsString();
    if (text.length > 5 * 1024 * 1024) throw const FormatException('too large');
    if (text.isEmpty) return {};
    final v = jsonDecode(text);
    if (v is! Map<String, dynamic>) throw const FormatException('object expected');
    return v;
  }

  static Response _json(Object body, [int status = 200]) => Response(status,
      body: jsonEncode(body), headers: {'content-type': 'application/json; charset=utf-8'});

  Middleware _errors() => (inner) => (r) async {
        try {
          return await inner(r);
        } on FormatException {
          return _json({'error': 'bad_request'}, 400);
        }
      };

  Middleware _cors() => (inner) => (r) async {
        final origin = r.headers['origin'];
        final allow = allowedOrigins.contains('*')
            ? '*'
            : (origin != null && allowedOrigins.contains(origin) ? origin : '');
        final headers = {
          if (allow.isNotEmpty) 'access-control-allow-origin': allow,
          'access-control-allow-headers': 'authorization, content-type',
          'access-control-allow-methods': 'GET, POST, OPTIONS',
          'vary': 'origin',
        };
        if (r.method == 'OPTIONS') return Response(204, headers: headers);
        final res = await inner(r);
        return res.change(headers: headers);
      };
}
