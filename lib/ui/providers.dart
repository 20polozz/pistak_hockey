import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../wear/wear_bridge.dart';

import '../auth/auth_service.dart';
import '../auth/remote_auth_service.dart';
import '../core/clock.dart';
import '../data/db/app_database.dart';
import '../data/repositories/drift_audio_repository.dart';
import '../data/repositories/drift_match_repository.dart';
import '../data/repositories/drift_team_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../domain/match/match_event.dart';
import '../domain/match/match_info.dart';
import '../domain/match/match_projector.dart';
import '../domain/match/match_state.dart';
import '../domain/audio/audio_recording.dart';
import '../domain/repositories/audio_repository.dart';
import '../domain/repositories/match_repository.dart';
import '../domain/repositories/team_repository.dart';
import '../domain/match/match_filter.dart';
import '../domain/team/team.dart';
import '../domain/sport/match_format.dart';
import '../services/audio/audio_playback_service.dart';
import '../services/transcription/transcription_queue.dart';
import '../services/transcription/transcription_service.dart';
import '../services/match_session_service.dart';
import '../sync/http_sync_api.dart';
import '../sync/remote_sync_api.dart';
import '../sync/sync_engine.dart';
import 'match_controller.dart';

// ------------------------------------------------- infrastructure (overridden)
final databaseProvider = Provider<AppDatabase>(
    (ref) => throw UnimplementedError('override in main'));
final deviceIdProvider =
    Provider<String>((ref) => throw UnimplementedError('override in main'));

final clockProvider = Provider<Clock>((ref) => const SystemClock());

final settingsRepositoryProvider = Provider<SettingsRepository>(
    (ref) => SettingsRepository(ref.watch(databaseProvider)));

final matchRepositoryProvider =
    Provider<MatchRepository>((ref) => DriftMatchRepository(
          ref.watch(databaseProvider),
          deviceId: ref.watch(deviceIdProvider),
          clock: ref.watch(clockProvider),
        ));

final audioRepositoryProvider = Provider<AudioRepository>((ref) =>
    DriftAudioRepository(ref.watch(databaseProvider),
        clock: ref.watch(clockProvider)));

/// Phase 4 replaces this with the backend Speech-to-Text client.
final transcriptionServiceProvider =
    Provider<TranscriptionService>((ref) => const NoTranscriptionService());

final transcriptionQueueProvider =
    Provider<TranscriptionQueue>((ref) => TranscriptionQueue(
          audio: ref.watch(audioRepositoryProvider),
          service: ref.watch(transcriptionServiceProvider),
          languageCode: ref.watch(localeCodeProvider),
        ));

final playbackServiceProvider = Provider<AudioPlaybackService>((ref) {
  final s = AudioPlaybackService();
  ref.onDispose(s.stop);
  return s;
});

final matchAudioProvider = StreamProvider.family<List<AudioRecording>, String>(
    (ref, id) => ref.watch(audioRepositoryProvider).watchByMatch(id));

/// User-defined categories (named formats). Invalidate after edits.
final categoriesProvider = FutureProvider<List<MatchFormat>>(
    (ref) => ref.watch(settingsRepositoryProvider).categories());

final teamRepositoryProvider = Provider<TeamRepository>((ref) =>
    DriftTeamRepository(ref.watch(databaseProvider),
        clock: ref.watch(clockProvider)));

final teamsProvider = StreamProvider<List<Team>>(
    (ref) => ref.watch(teamRepositoryProvider).watchTeams());

final teamMembersProvider = StreamProvider.family<List<TeamMember>, String>(
    (ref, teamId) => ref.watch(teamRepositoryProvider).watchMembers(teamId));

/// Current history filters (home screen).
final matchFilterProvider =
    StateProvider<MatchFilter>((ref) => const MatchFilter());

/// API base URL, set at build time:
///   flutter build web --dart-define=PISTAK_API_URL=https://api.example.com
/// Empty = no backend: the app works 100% locally (accounts hidden).
const apiBaseUrl = String.fromEnvironment('PISTAK_API_URL');
bool get isBackendConfigured => apiBaseUrl.isNotEmpty;

/// The account service when a backend is configured (overridden in main
/// after restoring the saved session), otherwise null.
final accountProvider =
    ChangeNotifierProvider<RemoteAuthService?>((ref) => null);

final authServiceProvider = Provider<AuthService>(
    (ref) => ref.watch(accountProvider) ?? const GuestAuthService());

final syncApiProvider = Provider<RemoteSyncApi>((ref) {
  final account = ref.watch(accountProvider);
  if (account == null) return const OfflineOnlyApi();
  return HttpSyncApi(baseUrl: apiBaseUrl, token: account.accessToken);
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final settings = ref.watch(settingsRepositoryProvider);
  final engine = SyncEngine(
    repository: ref.watch(matchRepositoryProvider),
    api: ref.watch(syncApiProvider),
    auth: ref.watch(authServiceProvider),
    readCursor: (uid) async =>
        int.tryParse(await settings.get('sync_cursor:$uid') ?? '') ?? 0,
    writeCursor: (uid, c) => settings.set('sync_cursor:$uid', '$c'),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

/// Keeps background sync running while signed in (watched by the app root).
final syncAutoStartProvider = Provider<void>((ref) {
  final engine = ref.watch(syncEngineProvider);
  if (ref.watch(authServiceProvider).isSignedIn) engine.start();
});

/// Connectivity changes (wifi/mobile/none) → try to sync right away.
final connectivityProvider = StreamProvider<List<ConnectivityResult>>(
    (ref) => Connectivity().onConnectivityChanged);

final sessionServiceProvider =
    Provider<MatchSessionService>((ref) => const MatchSessionService());

/// null = device language.
final localeCodeProvider = StateProvider<String?>((ref) => null);

// ------------------------------------------------------------------- queries
final matchesProvider = StreamProvider<List<MatchInfo>>(
    (ref) => ref.watch(matchRepositoryProvider).watchMatches());

final activeMatchProvider = StreamProvider<MatchInfo?>(
    (ref) => ref.watch(matchRepositoryProvider).watchActiveMatch());

final pendingCountProvider = StreamProvider<int>(
    (ref) => ref.watch(matchRepositoryProvider).watchPendingCount());

final matchProvider = StreamProvider.family<MatchInfo?, String>(
    (ref, id) => ref.watch(matchRepositoryProvider).watchMatch(id));

final matchEventsProvider = StreamProvider.family<List<MatchEvent>, String>(
    (ref, id) => ref.watch(matchRepositoryProvider).watchEvents(id));

/// Everything a match screen needs, derived from what is persisted.
class MatchView {
  const MatchView(this.info, this.events, this.state);
  final MatchInfo info;

  /// All events including voided ones, chronological.
  final List<MatchEvent> events;
  final MatchState state;

  Iterable<MatchEvent> get activeEvents => events.where((e) => !e.isVoided);
}

class MatchNotFound implements Exception {
  const MatchNotFound();
}

final matchViewProvider =
    Provider.family<AsyncValue<MatchView>, String>((ref, id) {
  final m = ref.watch(matchProvider(id));
  final ev = ref.watch(matchEventsProvider(id));
  if (m.hasError) {
    return AsyncValue.error(m.error!, m.stackTrace ?? StackTrace.current);
  }
  if (ev.hasError) {
    return AsyncValue.error(ev.error!, ev.stackTrace ?? StackTrace.current);
  }
  if (!m.hasValue || !ev.hasValue) return const AsyncValue.loading();
  final info = m.value;
  if (info == null) {
    return AsyncValue.error(const MatchNotFound(), StackTrace.current);
  }
  final events = ev.value!;
  return AsyncValue.data(MatchView(
      info, events, const MatchProjector().project(info.format, events)));
});

final matchControllerProvider =
    Provider.family<MatchController, String>((ref, id) => MatchController(
          matchId: id,
          deviceId: ref.watch(deviceIdProvider),
          repository: ref.watch(matchRepositoryProvider),
          clock: ref.watch(clockProvider),
          audio: ref.watch(audioRepositoryProvider),
        ));

/// Wear OS link (Android only; a no-op elsewhere).
final wearBridgeProvider = Provider<WearBridge>((ref) {
  final bridge = WearBridge(
    repository: ref.watch(matchRepositoryProvider),
    controllerFor: (id) => ref.read(matchControllerProvider(id)),
    clock: ref.watch(clockProvider),
  );
  ref.onDispose(bridge.dispose);
  return bridge;
});
