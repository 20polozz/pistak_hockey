import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Speech-to-Text provider used by `POST /transcribe`. The provider API key
/// lives only in the server environment — never in the app.
abstract class SpeechToText {
  Future<String> transcribe(Uint8List audio,
      {required String mimeType, String? language});
}

class SttError implements Exception {
  const SttError(this.message);
  final String message;
  @override
  String toString() => 'SttError($message)';
}

/// OpenAI-compatible `/audio/transcriptions` endpoint (Whisper and
/// compatible self-hosted servers). Multipart: file + model (+ language).
class OpenAiCompatibleStt implements SpeechToText {
  OpenAiCompatibleStt({
    required this.apiKey,
    this.endpoint = 'https://api.openai.com/v1/audio/transcriptions',
    this.model = 'whisper-1',
    http.Client? client,
    this.timeout = const Duration(seconds: 90),
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String endpoint;
  final String model;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<String> transcribe(Uint8List audio,
      {required String mimeType, String? language}) async {
    final ext = mimeType.contains('wav')
        ? 'wav'
        : mimeType.contains('mp4') || mimeType.contains('m4a')
            ? 'm4a'
            : mimeType.contains('ogg')
                ? 'ogg'
                : mimeType.contains('webm')
                    ? 'webm'
                    : 'bin';
    final req = http.MultipartRequest('POST', Uri.parse(endpoint))
      ..headers['authorization'] = 'Bearer $apiKey'
      ..fields['model'] = model
      ..fields['response_format'] = 'json'
      ..files.add(http.MultipartFile.fromBytes('file', audio, filename: 'incident.$ext'));
    if (language != null && RegExp(r'^[a-z]{2}$').hasMatch(language)) {
      req.fields['language'] = language;
    }
    final res = await http.Response.fromStream(await _client.send(req).timeout(timeout));
    if (res.statusCode != 200) {
      throw SttError('provider ${res.statusCode}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final text = body is Map ? body['text'] : null;
    if (text is! String) throw const SttError('unexpected provider response');
    return text.trim();
  }
}
