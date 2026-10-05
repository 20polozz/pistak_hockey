import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/match/match_event.dart';
import '../domain/match/match_info.dart';
import 'remote_sync_api.dart';

/// HTTPS client of the PISTAK API (backend/). Any network problem becomes a
/// [SyncUnavailable] so the engine just retries later; nothing local changes.
class HttpSyncApi implements RemoteSyncApi, DocSyncApi {
  HttpSyncApi({
    required this.baseUrl,
    required this.token,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final Future<String?> Function() token;
  final http.Client _client;
  final Duration timeout;

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q);

  Future<Map<String, String>> _headers() async {
    final t = await token();
    if (t == null) throw const SyncUnauthorized();
    return {
      'authorization': 'Bearer $t',
      'content-type': 'application/json',
    };
  }

  Future<Map<String, dynamic>> _send(
      Future<http.Response> Function() call) async {
    final res = await _raw(call);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<http.Response> _raw(Future<http.Response> Function() call,
      {bool allow404 = false}) async {
    final http.Response res;
    try {
      res = await call().timeout(timeout);
    } on TimeoutException {
      throw const SyncUnavailable('timeout');
    } catch (e) {
      if (e is SyncUnauthorized) rethrow;
      throw SyncUnavailable('$e');
    }
    if (res.statusCode == 401) throw const SyncUnauthorized();
    if (res.statusCode >= 500 || res.statusCode == 429) {
      throw SyncUnavailable('server ${res.statusCode}');
    }
    if (allow404 && res.statusCode == 404) return res;
    if (res.statusCode >= 400) {
      throw StateError('sync rejected ${res.statusCode}: ${res.body}');
    }
    return res;
  }

  Future<PushResult> _push(String key, List<Map<String, dynamic>> docs) async {
    final h = await _headers();
    final body = await _send(() => _client.post(_u('/sync/push'),
        headers: h, body: jsonEncode({key: docs})));
    final acc =
        (body['accepted'] as Map<String, dynamic>)[key] as Map<String, dynamic>;
    return PushResult(
        {for (final e in acc.entries) e.key: (e.value as num).toInt()});
  }

  @override
  Future<PushResult> pushMatches(List<MatchInfo> matches) =>
      _push('matches', [for (final m in matches) m.toJson()]);

  @override
  Future<PushResult> pushEvents(List<MatchEvent> events) =>
      _push('events', [for (final e in events) e.toJson()]);

  @override
  Future<PullResult> pull(int cursor) async {
    final h = await _headers();
    final body = await _send(
        () => _client.get(_u('/sync/pull', {'since': '$cursor'}), headers: h));
    List<Map<String, dynamic>> list(String k) => [
          for (final x in (body[k] as List? ?? const []))
            Map<String, dynamic>.from(x as Map)
        ];
    return PullResult(
      matches: list('matches'),
      events: list('events'),
      docs: {
        for (final k in const ['teams', 'members', 'audio']) k: list(k)
      },
      cursor: (body['cursor'] as num?)?.toInt() ?? cursor,
    );
  }

  @override
  Future<PushResult> pushDocs(String key, List<Map<String, dynamic>> docs) =>
      _push(key, docs);

  @override
  Future<void> uploadBlob(String id, Uint8List bytes, String mimeType) async {
    final h = await _headers();
    await _raw(() => _client.put(_u('/audio/$id'),
        headers: {...h, 'content-type': mimeType}, body: bytes));
  }

  @override
  Future<Uint8List?> downloadBlob(String id) async {
    final h = await _headers();
    final res = await _raw(() => _client.get(_u('/audio/$id'), headers: h),
        allow404: true);
    return res.statusCode == 404 ? null : res.bodyBytes;
  }
}
