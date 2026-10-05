import 'dart:async';
import 'dart:math';

import '../auth/auth_service.dart';
import '../domain/repositories/match_repository.dart';
import 'remote_sync_api.dart';

enum SyncState { localOnly, idle, syncing, offline }

class SyncReport {
  const SyncReport({this.matches = 0, this.events = 0, this.error});
  final int matches;
  final int events;
  final Object? error;
  bool get ok => error == null;
}

/// Pushes the local outbox (rows with syncStatus = pending) to the server.
///
/// * Never blocks the UI and never deletes local data.
/// * Safe to run concurrently with match recording: a row edited while being
///   sent keeps its pending state (revision check in markXxxSynced).
/// * Safe to retry: the server deduplicates by id.
class SyncEngine {
  SyncEngine({
    required this.repository,
    required this.api,
    required this.auth,
    this.batchSize = 200,
    this.baseRetry = const Duration(seconds: 5),
    this.maxRetry = const Duration(minutes: 5),
  });

  final MatchRepository repository;
  final RemoteSyncApi api;
  final AuthService auth;
  final int batchSize;
  final Duration baseRetry;
  final Duration maxRetry;

  final _state = StreamController<SyncState>.broadcast();
  SyncState _current = SyncState.localOnly;
  Future<SyncReport>? _running;
  Timer? _timer;
  int _failures = 0;

  Stream<SyncState> get states => _state.stream;
  SyncState get state => _current;

  void _set(SyncState s) {
    _current = s;
    if (!_state.isClosed) _state.add(s);
  }

  /// Starts periodic background sync (call when the user signs in).
  void start() {
    _schedule(Duration.zero);
  }

  /// Hint that connectivity / app focus changed: try now.
  void poke() => _schedule(Duration.zero);

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () async {
      final report = await syncOnce();
      if (report.ok) {
        _failures = 0;
        _schedule(const Duration(seconds: 30));
      } else {
        _failures++;
        final ms = min(maxRetry.inMilliseconds,
            baseRetry.inMilliseconds * pow(2, _failures - 1).toInt());
        _schedule(Duration(milliseconds: ms));
      }
    });
  }

  /// One full push cycle. Concurrent calls share the same run.
  Future<SyncReport> syncOnce() => _running ??= _run().whenComplete(() {
        _running = null;
      });

  Future<SyncReport> _run() async {
    if (!auth.isSignedIn) {
      _set(SyncState.localOnly);
      return const SyncReport();
    }
    _set(SyncState.syncing);
    var matches = 0;
    var events = 0;
    try {
      // Matches first so the server knows the parent of every event.
      while (true) {
        final batch = await repository.pendingMatches(limit: batchSize);
        if (batch.isEmpty) break;
        final res = await api.pushMatches(batch);
        await repository.markMatchesSynced(res.accepted);
        matches += res.accepted.length;
        if (batch.length < batchSize || res.accepted.isEmpty) break;
      }
      while (true) {
        final batch = await repository.pendingEvents(limit: batchSize);
        if (batch.isEmpty) break;
        final res = await api.pushEvents(batch);
        await repository.markEventsSynced(res.accepted);
        events += res.accepted.length;
        if (batch.length < batchSize || res.accepted.isEmpty) break;
      }
      _set(SyncState.idle);
      return SyncReport(matches: matches, events: events);
    } catch (e) {
      _set(SyncState.offline);
      return SyncReport(matches: matches, events: events, error: e);
    }
  }

  void dispose() {
    _timer?.cancel();
    _state.close();
  }
}
