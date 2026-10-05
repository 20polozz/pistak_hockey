import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pistak_server/pistak_server.dart';
import 'package:test/test.dart';

void main() {
  test('OpenAI-compatible provider: multipart request and parsing', () async {
    late http.Request seen;
    final stt = OpenAiCompatibleStt(
      apiKey: 'server-side-key',
      endpoint: 'https://stt.example/v1/audio/transcriptions',
      client: MockClient((r) async {
        seen = r;
        return http.Response(jsonEncode({'text': '  Gol en pròpia porta  '}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
    final text = await stt.transcribe(Uint8List.fromList([82, 73, 70, 70]),
        mimeType: 'audio/wav', language: 'ca');
    expect(text, 'Gol en pròpia porta');
    expect(seen.url.host, 'stt.example');
    expect(seen.headers['authorization'], 'Bearer server-side-key');
    final body = latin1.decode(seen.bodyBytes);
    expect(body, contains('name="model"'));
    expect(body, contains('whisper-1'));
    expect(body, contains('name="language"'));
    expect(body, contains('filename="incident.wav"'));
  });

  test('provider errors become SttError (no audio echoed)', () async {
    final stt = OpenAiCompatibleStt(
        apiKey: 'k', client: MockClient((_) async => http.Response('quota', 429)));
    await expectLater(stt.transcribe(Uint8List(4), mimeType: 'audio/wav'),
        throwsA(isA<SttError>()));
  });
}
