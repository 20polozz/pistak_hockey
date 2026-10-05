import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pistak/core/clock.dart';
import 'package:pistak/data/db/app_database.dart';
import 'package:pistak/data/repositories/drift_audio_repository.dart';
import 'package:pistak/data/repositories/drift_match_repository.dart';
import 'package:pistak/domain/audio/audio_recording.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';
import 'package:pistak/services/transcription/http_transcription_service.dart';
import 'package:pistak/services/transcription/transcription_queue.dart';
import 'package:pistak/services/transcription/transcription_service.dart';
import 'package:pistak/ui/match_controller.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  MockClient server(
          {bool stt = true, int status = 200, String text = 'Hola'}) =>
      MockClient((r) async {
        if (r.url.path == '/health') {
          return http.Response(jsonEncode({'ok': true, 'stt': stt}), 200);
        }
        expect(r.url.path, '/transcribe');
        expect(r.headers['authorization'], 'Bearer tok');
        if (status != 200) return http.Response('{}', status);
        return http.Response(jsonEncode({'text': text}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });

  HttpTranscriptionService svc(MockClient c, {String? token = 'tok'}) =>
      HttpTranscriptionService(
          baseUrl: 'https://api.test', token: () async => token, client: c);

  test('guests never send audio anywhere', () async {
    var calls = 0;
    final s = svc(MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    }), token: null);
    expect(await s.isAvailable(), isFalse);
    expect(calls, 0);
  });

  test('availability follows the server health (stt flag)', () async {
    expect(await svc(server()).isAvailable(), isTrue);
    expect(await svc(server(stt: false)).isAvailable(), isFalse);
    expect(
        await svc(MockClient((_) async => throw Exception('offline')))
            .isAvailable(),
        isFalse);
  });

  test('status codes: transient vs real failures', () async {
    final audio = Uint8List(10);
    expect(
        await svc(server(text: 'Falta clara'))
            .transcribe(audio, mimeType: 'audio/wav', languageCode: 'ca'),
        'Falta clara');
    for (final code in [401, 429, 503, 500]) {
      await expectLater(
          svc(server(status: code)).transcribe(audio, mimeType: 'audio/wav'),
          throwsA(isA<TranscriptionUnavailable>()),
          reason: '$code');
    }
    await expectLater(
        svc(server(status: 502)).transcribe(audio, mimeType: 'audio/wav'),
        throwsA(isA<StateError>()));
  });

  test('queue + backend: voice incident gets its text', () async {
    final clock = FakeClock(DateTime.utc(2026, 10, 12, 18));
    final db = AppDatabase(NativeDatabase.memory());
    final repo = DriftMatchRepository(db, deviceId: 'd', clock: clock);
    final audio = DriftAudioRepository(db, clock: clock);
    final m = await repo.createMatch(
        sport: rollerHockey.id, format: rollerHockey.defaultFormat);
    final c = MatchController(
        matchId: m.id,
        deviceId: 'd',
        repository: repo,
        clock: clock,
        audio: audio);
    await c.startMatch();
    final ev = (await c.voiceIncident(
            bytes: Uint8List(100),
            mimeType: 'audio/wav',
            duration: const Duration(seconds: 1),
            at: clock.now()))
        .single;

    // Server down first: stays pending, nothing lost.
    final down = TranscriptionQueue(
        audio: audio, service: svc(server(status: 503)), languageCode: 'ca');
    expect((await down.processPending()).done, 0);
    expect(await audio.pendingTranscriptions(), hasLength(1));

    final up = TranscriptionQueue(
        audio: audio,
        service: svc(server(text: 'Discussió a la banqueta')),
        languageCode: 'ca');
    expect((await up.processPending()).done, 1);
    final stored =
        (await repo.getEvents(m.id)).firstWhere((e) => e.id == ev.id);
    expect(stored.text, 'Discussió a la banqueta');
    expect(await audio.pendingTranscriptions(), isEmpty);
    final rec = await audio.get(stored.metadata['audioId'] as String);
    expect(rec!.transcriptStatus, TranscriptStatus.done);
    await db.close();
  });
}
