import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/core/clock.dart';
import 'package:pistak/core/wav.dart';
import 'package:pistak/data/db/app_database.dart';
import 'package:pistak/data/repositories/drift_audio_repository.dart';
import 'package:pistak/data/repositories/drift_match_repository.dart';
import 'package:pistak/data/repositories/settings_repository.dart';
import 'package:pistak/domain/audio/audio_recording.dart';
import 'package:pistak/domain/match/match_event.dart';
import 'package:pistak/domain/sport/match_format.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';
import 'package:pistak/services/transcription/transcription_queue.dart';
import 'package:pistak/services/transcription/transcription_service.dart';
import 'package:pistak/ui/match_controller.dart';

class FakeStt implements TranscriptionService {
  bool online = false;
  bool fail = false;
  int calls = 0;

  @override
  Future<bool> isAvailable() async => online;

  @override
  Future<String> transcribe(Uint8List audio,
      {required String mimeType, String? languageCode}) async {
    calls++;
    if (!online) throw const TranscriptionUnavailable('offline');
    if (fail) throw Exception('bad audio');
    return '  Tarjeta azul al número 8 visitante por protestar  ';
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DriftMatchRepository matches;
  late DriftAudioRepository audio;
  late FakeClock clock;
  late MatchController c;
  late String matchId;
  final wav = pcm16ToWav(Uint8List(3200), sampleRate: 16000, channels: 1);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    clock = FakeClock(DateTime.utc(2026, 10, 12, 18, 30));
    matches = DriftMatchRepository(db, deviceId: 'd1', clock: clock);
    audio = DriftAudioRepository(db, clock: clock);
    final m = await matches.createMatch(
        sport: rollerHockey.id, format: rollerHockey.defaultFormat);
    matchId = m.id;
    c = MatchController(
        matchId: matchId,
        deviceId: 'd1',
        repository: matches,
        clock: clock,
        audio: audio);
    await c.startMatch();
  });

  tearDown(() => db.close());

  Future<MatchEvent> recordVoice() async {
    final at = clock.now();
    clock.advance(const Duration(seconds: 8)); // time spent talking
    final ev = await c.voiceIncident(
        bytes: wav,
        mimeType: 'audio/wav',
        duration: const Duration(milliseconds: 100),
        at: at);
    return ev.single;
  }

  test('voice incident is stored locally, stamped at the tap, pending STT',
      () async {
    clock.advance(const Duration(minutes: 9, seconds: 21));
    final e = await recordVoice();
    expect(e.type, EventTypes.incident);
    expect(e.subtype, IncidentKinds.voice);
    expect(e.matchTime, const Duration(minutes: 9, seconds: 21));
    final id = e.metadata[MetaKeys.audioId] as String;
    final rec = (await audio.get(id))!;
    expect(rec.eventId, e.id);
    expect(rec.bytes, wav);
    expect(rec.transcriptStatus, TranscriptStatus.pending);
    expect((await audio.pendingTranscriptions()).single.id, id);
  });

  test('offline: transcription is skipped and the match is unaffected',
      () async {
    final stt = FakeStt();
    await recordVoice();
    final q = TranscriptionQueue(audio: audio, service: stt);
    final r = await q.processPending();
    expect(r.skipped, isTrue);
    expect(stt.calls, 0);
    expect((await audio.pendingTranscriptions()).length, 1);
    expect((await c.currentState()).incidents, 1);
  });

  test('back online: transcript becomes the editable incident text', () async {
    final stt = FakeStt()..online = true;
    final e = await recordVoice();
    final r =
        await TranscriptionQueue(audio: audio, service: stt).processPending();
    expect(r.done, 1);
    final stored = (await matches.getEvents(matchId))
        .firstWhere((x) => x.id == e.id);
    expect(stored.text, 'Tarjeta azul al número 8 visitante por protestar');
    expect(stored.revision, 2);
    expect(stored.syncStatus, SyncStatus.pending);
    expect(await audio.pendingTranscriptions(), isEmpty);
    // Running again does nothing.
    expect((await TranscriptionQueue(audio: audio, service: stt)
            .processPending())
        .done, 0);
  });

  test('a text typed by the user is never overwritten by STT', () async {
    final stt = FakeStt()..online = true;
    final e = await recordVoice();
    await c.updateEvent(e.copyWith(
        metadata: {...e.metadata, MetaKeys.text: 'Escrit a mà'}));
    await TranscriptionQueue(audio: audio, service: stt).processPending();
    final stored = (await matches.getEvents(matchId))
        .firstWhere((x) => x.id == e.id);
    expect(stored.text, 'Escrit a mà');
  });

  test('repeated STT errors mark it failed but keep the audio', () async {
    final stt = FakeStt()
      ..online = true
      ..fail = true;
    final e = await recordVoice();
    final q = TranscriptionQueue(audio: audio, service: stt);
    for (var i = 0; i < 5; i++) {
      await q.processPending();
    }
    final rec = (await audio.get(e.metadata[MetaKeys.audioId] as String))!;
    expect(rec.transcriptStatus, TranscriptStatus.failed);
    expect(rec.attempts, 5);
    expect(rec.hasAudio, isTrue);
  });

  test('deleting the audio keeps the incident (privacy)', () async {
    final e = await recordVoice();
    final id = e.metadata[MetaKeys.audioId] as String;
    await audio.deleteAudio(id);
    final rec = (await audio.get(id))!;
    expect(rec.hasAudio, isFalse);
    expect(await audio.pendingTranscriptions(), isEmpty);
    expect((await c.currentState()).incidents, 1);
  });

  test('categories (named formats) are saved, edited and deleted', () async {
    final settings = SettingsRepository(db);
    const alevi = MatchFormat(
        id: 'cat_alevi',
        name: 'Aleví',
        periods: 2,
        periodDuration: Duration(minutes: 15),
        breakDuration: Duration(minutes: 5),
        timeoutDuration: Duration(seconds: 45));
    await settings.saveCategory(alevi);
    expect(await settings.categories(), [alevi]);
    await settings.saveCategory(alevi.copyWith(periods: 3));
    expect((await settings.categories()).single.periods, 3);
    await settings.deleteCategory('cat_alevi');
    expect(await settings.categories(), isEmpty);
  });
}
