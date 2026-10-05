import '../core/clock.dart';
import 'dart:typed_data';

import '../core/ids.dart';
import '../domain/audio/audio_recording.dart';
import '../domain/match/event_factory.dart';
import '../domain/match/match_event.dart';
import '../domain/match/match_projector.dart';
import '../domain/match/match_state.dart';
import '../domain/repositories/audio_repository.dart';
import '../domain/repositories/match_repository.dart';

/// Executes user actions on one match.
///
/// * The instant of the tap is captured immediately ([Clock.now]) and used
///   for the event, even if the write is queued behind a previous one.
/// * Actions run strictly one after another (serial queue), each one reading
///   the latest persisted state, so fast double taps can't interleave.
/// * The UI never updates from memory: it listens to the database, so what
///   is shown is always what is saved.
class MatchController {
  MatchController({
    required this.matchId,
    required this.deviceId,
    required this.repository,
    required this.clock,
    this.audio,
    this.ids = const UuidV7Generator(),
    this.projector = const MatchProjector(),
  });

  final String matchId;
  final String deviceId;
  final MatchRepository repository;
  final Clock clock;
  final AudioRepository? audio;
  final IdGenerator ids;
  final MatchProjector projector;

  Future<void> _tail = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<MatchState> currentState() async {
    final info = await repository.getMatch(matchId);
    if (info == null) throw StateError('Match $matchId not found');
    return projector.project(info.format, await repository.getEvents(matchId));
  }

  Future<List<MatchEvent>> _act(
      List<MatchEvent> Function(EventFactory f, MatchState s) build,
      {DateTime? at, Future<void> Function(List<MatchEvent> events)? before}) {
    final tapTime = at ?? clock.now();
    return _serial(() async {
      final state = await currentState();
      final factory = EventFactory(
        matchId: matchId,
        deviceId: deviceId,
        clock: FixedClock(tapTime),
        ids: ids,
      );
      final events = build(factory, state);
      if (events.isEmpty) return const <MatchEvent>[];
      if (before != null) await before(events);
      return repository.appendEvents(matchId, events);
    });
  }

  // clock
  Future<List<MatchEvent>> startMatch() => _act((f, s) => f.startMatch(s));
  Future<List<MatchEvent>> pause() => _act((f, s) => f.pause(s));
  Future<List<MatchEvent>> resume() => _act((f, s) => f.resume(s));
  Future<List<MatchEvent>> endPeriod(
          {PeriodEndChoice then = PeriodEndChoice.endMatch}) =>
      _act((f, s) => f.endPeriod(s, then: then));
  Future<List<MatchEvent>> startShootout() =>
      _act((f, s) => f.startShootout(s));
  Future<List<MatchEvent>> shootoutAttempt(TeamSide team,
          {required bool scored}) =>
      _act((f, s) => f.shootoutAttempt(s, team, scored: scored));
  Future<List<MatchEvent>> startNextPeriod() =>
      _act((f, s) => f.startNextPeriod(s));
  Future<List<MatchEvent>> endMatch() => _act((f, s) => f.endMatch(s));
  Future<List<MatchEvent>> adjustClock(Duration periodElapsed) =>
      _act((f, s) => f.adjustClock(s, periodElapsed));

  // recording
  Future<List<MatchEvent>> goal(TeamSide team) =>
      _act((f, s) => f.goal(s, team));
  Future<List<MatchEvent>> foul(TeamSide team) =>
      _act((f, s) => f.foul(s, team));
  Future<List<MatchEvent>> card(String color, {TeamSide? team}) =>
      _act((f, s) => f.card(s, color, team: team));
  Future<List<MatchEvent>> timeout(TeamSide team) =>
      _act((f, s) => f.timeout(s, team));
  Future<List<MatchEvent>> endTimeout() => _act((f, s) => f.endTimeout(s));

  /// [at] = moment the user pressed INCIDÈNCIA (before typing/recording).
  Future<List<MatchEvent>> incident(String kind,
          {String? text, DateTime? at, Map<String, dynamic> extra = const {}}) =>
      _act((f, s) => f.incident(s, kind: kind, text: text, extra: extra),
          at: at);

  /// Voice incident: the audio is stored locally first, then the incident
  /// event (pointing to it). Transcription happens later, decoupled.
  Future<List<MatchEvent>> voiceIncident({
    required Uint8List bytes,
    required String mimeType,
    required Duration duration,
    required DateTime at,
  }) {
    final store = audio;
    if (store == null) throw StateError('No audio repository configured');
    final audioId = ids.newId();
    return _act(
      (f, s) => f.incident(s, kind: IncidentKinds.voice, extra: {
        MetaKeys.audioId: audioId,
        MetaKeys.transcriptStatus: TranscriptStatus.pending.code,
      }),
      at: at,
      before: (events) => store.save(AudioRecording(
        id: audioId,
        matchId: matchId,
        eventId: events.first.id,
        mimeType: mimeType,
        duration: duration,
        sizeBytes: bytes.length,
        bytes: bytes,
        createdAt: at,
        updatedAt: at,
      )),
    );
  }

  // corrections
  Future<List<MatchEvent>> undo() =>
      _serial(() => repository.undoLastAction(matchId));

  Future<void> setTeam(MatchEvent e, TeamSide? team) => _serial(() =>
      repository.updateEvent(e.copyWith(team: team, clearTeam: team == null)));

  Future<void> updateEvent(MatchEvent e) =>
      _serial(() => repository.updateEvent(e));

  Future<void> setVoided(MatchEvent e, bool voided) =>
      _serial(() => repository.setEventVoided(e.id, voided: voided));
}
