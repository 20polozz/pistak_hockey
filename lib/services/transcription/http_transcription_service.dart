import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'transcription_service.dart';

/// Speech-to-Text through the PISTAK backend (`POST /transcribe`). The
/// provider key stays on the server; the app only sends the user's token.
class HttpTranscriptionService implements TranscriptionService {
  HttpTranscriptionService({
    required this.baseUrl,
    required this.token,
    http.Client? client,
    this.timeout = const Duration(seconds: 120),
    this.availabilityTtl = const Duration(minutes: 5),
    DateTime Function()? now,
  })  : _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  final String baseUrl;
  final Future<String?> Function() token;
  final http.Client _client;
  final Duration timeout;
  final Duration availabilityTtl;
  final DateTime Function() _now;

  bool? _available;
  DateTime? _checkedAt;

  @override
  Future<bool> isAvailable() async {
    if (await token() == null) return false; // guest: nothing leaves the device
    final at = _checkedAt;
    if (_available != null &&
        at != null &&
        _now().difference(at) < availabilityTtl) {
      return _available!;
    }
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      _available = res.statusCode == 200 && body is Map && body['stt'] == true;
    } on Object {
      _available = false; // offline: try again later
    }
    _checkedAt = _now();
    return _available!;
  }

  @override
  Future<String> transcribe(Uint8List audio,
      {required String mimeType, String? languageCode}) async {
    final t = await token();
    if (t == null) throw const TranscriptionUnavailable('not signed in');
    final uri = Uri.parse('$baseUrl/transcribe').replace(
        queryParameters: languageCode == null ? null : {'lang': languageCode});
    final http.Response res;
    try {
      res = await _client
          .post(uri,
              headers: {'authorization': 'Bearer $t', 'content-type': mimeType},
              body: audio)
          .timeout(timeout);
    } on Object catch (e) {
      throw TranscriptionUnavailable('$e');
    }
    final code = res.statusCode;
    if (code == 200) {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final text = body is Map ? body['text'] : null;
      if (text is! String) throw const FormatException('no text');
      return text;
    }
    // Session expired, rate limit, not configured, server down: transient,
    // the recording stays pending and is retried later.
    if (code == 401 || code == 429 || (code >= 500 && code != 502)) {
      if (code == 503) _available = false;
      throw TranscriptionUnavailable('server $code');
    }
    // 502 = the provider failed on this audio; other 4xx = bad request.
    throw StateError('transcription failed ($code)');
  }
}
