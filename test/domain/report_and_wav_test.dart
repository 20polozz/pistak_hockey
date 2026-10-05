import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/core/clock.dart';
import 'package:pistak/core/ids.dart';
import 'package:pistak/core/wav.dart';
import 'package:pistak/domain/match/event_factory.dart';
import 'package:pistak/domain/match/match_event.dart';
import 'package:pistak/domain/match/match_info.dart';
import 'package:pistak/domain/match/match_projector.dart';
import 'package:pistak/domain/report/match_report.dart';
import 'package:pistak/domain/report/report_exporter.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';

void main() {
  group('WAV', () {
    test('header describes PCM16 mono 16 kHz', () {
      final pcm = Uint8List(32000); // 1 s
      final wav = pcm16ToWav(pcm, sampleRate: 16000, channels: 1);
      final h = ByteData.sublistView(wav);
      expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
      expect(h.getUint32(4, Endian.little), 36 + 32000);
      expect(h.getUint16(22, Endian.little), 1);
      expect(h.getUint32(24, Endian.little), 16000);
      expect(h.getUint32(40, Endian.little), 32000);
      expect(wav.length, 44 + 32000);
      expect(pcm16Duration(32000, sampleRate: 16000, channels: 1),
          const Duration(seconds: 1));
    });
  });

  group('Reports', () {
    final clock = FakeClock(DateTime.utc(2026, 10, 12, 16, 30));
    final f = EventFactory(
        matchId: 'm1',
        deviceId: 'd1',
        clock: clock,
        ids: SequentialIdGenerator());
    final events = <MatchEvent>[];
    void run(List<MatchEvent> Function() c) => events.addAll(c());
    final info = MatchInfo(
      id: 'm1',
      sport: rollerHockey.id,
      format: rollerHockey.defaultFormat,
      homeName: 'CP Exemple',
      awayName: 'HC Exemple',
      createdAt: clock.now(),
      updatedAt: clock.now(),
      deviceId: 'd1',
    );

    setUpAll(() {
      const p = MatchProjector();
      run(() => f.startMatch(p.project(info.format, events)));
      clock.advance(const Duration(minutes: 3, seconds: 42));
      run(() => f.goal(p.project(info.format, events), TeamSide.home));
      clock.advance(const Duration(minutes: 1));
      run(() => f.incident(p.project(info.format, events),
          kind: IncidentKinds.text, text: 'Pista mullada, "aturada", 2 min'));
      clock.advance(const Duration(minutes: 1));
      final voidMe = f.goal(p.project(info.format, events), TeamSide.away);
      events.addAll(voidMe.map((e) => e.copyWith(voidedAt: clock.now())));
    });

    test('report ignores voided events and tracks the running score', () {
      final r = MatchReport.build(info, events);
      expect(r.lines.length, 4);
      expect(r.state.home.goals, 1);
      expect(r.state.away.goals, 0);
      expect(r.lines.last.homeScore, 1);
    });

    test('CSV export escapes text and has one row per event', () {
      final csv =
          const CsvReportExporter().export(MatchReport.build(info, events));
      final rows = const LineSplitter().convert(csv);
      expect(rows.first, CsvReportExporter.header.join(','));
      expect(rows.length, 5);
      expect(rows[3], startsWith('03:42,1,GOAL,,home,,1,0,'));
      expect(csv, contains('"Pista mullada, ""aturada"", 2 min"'));
    });

    test('JSON export is valid and complete', () {
      final json = jsonDecode(const JsonReportExporter()
          .export(MatchReport.build(info, events))) as Map<String, dynamic>;
      expect(json['format'], 'pistak.match.v1');
      expect((json['events'] as List).length, 4);
      expect(json['stats']['home']['goals'], 1);
      expect(json['match']['homeName'], 'CP Exemple');
    });
  });
}
