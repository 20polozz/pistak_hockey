import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'security.dart';
import 'store.dart';
import 'stt.dart';

/// HTTP API:
///   GET  /health
///   POST /auth/register {email, password}      → {token, userId, email}
///   POST /auth/login    {email, password}      → {token, userId, email}
///   POST /sync/push     {matches:[], events:[], teams:[], members:[], audio:[]} (Bearer)
///                         → {accepted:{KEY:{id:rev}}, rejected:{id:reason}}
///   GET  /sync/pull?since=N                     (Bearer) → {KEY:[], cursor}
///   PUT  /audio/ID    raw bytes (Bearer)      → {ok}   (voice-incident audio)
///   GET  /audio/ID                  (Bearer)  → raw bytes
///   POST /transcribe?lang=ca  raw audio (Bearer) → {text}   (503 if no STT configured)
class PistakApi {
  PistakApi({
    required this.store,
    required this.jwt,
    PasswordHasher? hasher,
    this.maxBatch = 500,
    this.allowedOrigins = const ['*'],
    this.maxAudioBytes = 25 * 1024 * 1024,
    this.stt,
    this.maxTranscriptionsPerHour = 120,
  }) : hasher = hasher ?? PasswordHasher();

  final Store store;
  final Jwt jwt;
  final PasswordHasher hasher;
  final int maxBatch;
  final List<String> allowedOrigins;
  final int maxAudioBytes;
  final SpeechToText? stt;
  final int maxTranscriptionsPerHour;
  final _sttUse = <String, List<DateTime>>{};

  /// JSON key in push/pull → document kind stored on the server.
  static const kinds = {
    'matches': 'match',
    'events': 'event',
    'teams': 'team',
    'members': 'member',
    'audio': 'audio',
  };
  final _failures = <String, List<DateTime>>{};
  final _rnd = Random.secure();

  Handler get handler => const Pipeline()
      .addMiddleware(_cors())
      .addMiddleware(_errors())
      .addHandler(_router.call);

  Router get _router => Router()
    ..get('/health',
        (Request r) => _json({'ok': true, 'service': 'pistak', 'stt': stt != null}))
    ..post('/transcribe', _transcribe)
    ..post('/auth/register', _register)
    ..post('/auth/login', _login)
    ..post('/sync/push', _push)
    ..get('/sync/pull', _pull)
    ..put('/audio/<id>', _putAudio)
    ..get('/audio/<id>', _getAudio);

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
    final lists = {
      for (final k in kinds.keys) k: (body[k] as List?) ?? const <dynamic>[],
    };
    final total = lists.values.fold<int>(0, (a, l) => a + l.length);
    if (total > maxBatch) {
      return _json({'error': 'batch_too_large', 'max': maxBatch}, 413);
    }
    final accepted = <String, Map<String, int>>{};
    final rejected = <String, String>{};
    for (final entry in lists.entries) {
      final acc = accepted[entry.key] = <String, int>{};
      for (final d in entry.value) {
        if (d is! Map<String, dynamic>) continue;
        final res = store.upsert(kinds[entry.key]!, uid, d);
        final id = d['id'] as String? ?? '?';
        if (res.revision != null) {
          acc[id] = res.revision!;
          // Privacy: audio removed on a device is removed here too.
          if (entry.key == 'audio' && d['hasAudio'] == false && res.revision == d['revision']) {
            store.deleteBlob(id, uid);
          }
        } else {
          rejected[id] = res.rejected!;
        }
      }
    }
    return _json({'accepted': accepted, 'rejected': rejected});
  }

  Future<Response> _pull(Request r) async {
    final uid = _user(r);
    if (uid == null) return _json({'error': 'unauthorized'}, 401);
    final since = int.tryParse(r.url.queryParameters['since'] ?? '0') ?? 0;
    final c = store.changesSince(uid, since);
    return _json({
      for (final e in kinds.entries) e.key: c.byKind[e.value] ?? const [],
      'cursor': c.cursor,
    });
  }

  static final _idRe = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// Reads a binary body; null if larger than [maxAudioBytes].
  Future<Uint8List?> _bytes(Request r) async {
    final len = r.contentLength;
    if (len != null && len > maxAudioBytes) return null;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in r.read()) {
      builder.add(chunk);
      if (builder.length > maxAudioBytes) return null;
    }
    return builder.takeBytes();
  }

  static String _mime(Request r) =>
      (r.headers['content-type'] ?? 'application/octet-stream').split(';').first.trim();

  Future<Response> _transcribe(Request r) async {
    final uid = _user(r);
    if (uid == null) return _json({'error': 'unauthorized'}, 401);
    final provider = stt;
    if (provider == null) return _json({'error': 'stt_not_configured'}, 503);
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    final used = (_sttUse[uid] ??= [])..removeWhere((t) => t.isBefore(cutoff));
    if (used.length >= maxTranscriptionsPerHour) {
      return _json({'error': 'too_many_requests'}, 429);
    }
    final audio = await _bytes(r);
    if (audio == null) return _json({'error': 'too_large'}, 413);
    if (audio.isEmpty) return _json({'error': 'empty'}, 400);
    used.add(DateTime.now());
    try {
      final text = await provider.transcribe(audio,
          mimeType: _mime(r), language: r.url.queryParameters['lang']);
      return _json({'text': text});
    } on Object catch (e) {
      // Audio is never stored or logged here; only the failure kind.
      return _json({'error': 'stt_failed', 'detail': e is SttError ? e.message : 'error'}, 502);
    }
  }

  Future<Response> _putAudio(Request r, String id) async {
    final uid = _user(r);
    if (uid == null) return _json({'error': 'unauthorized'}, 401);
    if (!_idRe.hasMatch(id)) return _json({'error': 'bad_id'}, 400);
    final bytes = await _bytes(r);
    if (bytes == null) return _json({'error': 'too_large'}, 413);
    if (bytes.isEmpty) return _json({'error': 'empty'}, 400);
    final mime = _mime(r);
    if (!store.putBlob(id, uid, mime, bytes)) {
      return _json({'error': 'forbidden'}, 403);
    }
    return _json({'ok': true});
  }

  Future<Response> _getAudio(Request r, String id) async {
    final uid = _user(r);
    if (uid == null) return _json({'error': 'unauthorized'}, 401);
    final b = store.getBlob(id, uid);
    if (b == null) return _json({'error': 'not_found'}, 404);
    return Response.ok(b.bytes, headers: {'content-type': b.mime, 'cache-control': 'private, no-store'});
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
          'access-control-allow-methods': 'GET, POST, PUT, OPTIONS',
          'vary': 'origin',
        };
        if (r.method == 'OPTIONS') return Response(204, headers: headers);
        final res = await inner(r);
        return res.change(headers: headers);
      };
}
