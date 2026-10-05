import 'dart:typed_data';

import '../domain/match/match_event.dart';
import '../domain/match/match_info.dart';

/// Result of a push: the server returns the (id, revision) it has stored for
/// each item. Already-known ids are reported as accepted too (idempotency).
class PushResult {
  const PushResult(this.accepted);
  final Map<String, int> accepted;
}

/// Contract with the backend (implemented over HTTPS in Phase 2).
///
/// Server rule: INSERT ... ON CONFLICT (id) DO UPDATE only when the incoming
/// revision is higher → sending the same event N times stores it once.
abstract class RemoteSyncApi {
  Future<PushResult> pushMatches(List<MatchInfo> matches);
  Future<PushResult> pushEvents(List<MatchEvent> events);

  /// Changes made on other devices since [cursor] (server sequence).
  Future<PullResult> pull(int cursor);
}

/// Raw documents from the server (same JSON as MatchInfo/MatchEvent.toJson).
class PullResult {
  const PullResult({
    this.matches = const [],
    this.events = const [],
    this.docs = const {},
    required this.cursor,
  });
  final List<Map<String, dynamic>> matches;
  final List<Map<String, dynamic>> events;

  /// Other synced documents by key ('teams', 'members', 'audio').
  final Map<String, List<Map<String, dynamic>>> docs;
  final int cursor;

  int get size =>
      matches.length +
      events.length +
      docs.values.fold<int>(0, (a, l) => a + l.length);
  bool get isEmpty => size == 0;
}

/// Extra documents (teams, rosters, audio) and audio bytes.
/// Same idempotency rule as [RemoteSyncApi].
abstract class DocSyncApi {
  Future<PushResult> pushDocs(String key, List<Map<String, dynamic>> docs);
  Future<void> uploadBlob(String id, Uint8List bytes, String mimeType);

  /// null = the server doesn't have it (yet).
  Future<Uint8List?> downloadBlob(String id);
}

/// Phase 1: no backend. Nothing leaves the device.
class OfflineOnlyApi implements RemoteSyncApi {
  const OfflineOnlyApi();

  @override
  Future<PushResult> pushEvents(List<MatchEvent> events) =>
      throw const SyncUnavailable('no backend configured');

  @override
  Future<PushResult> pushMatches(List<MatchInfo> matches) =>
      throw const SyncUnavailable('no backend configured');

  @override
  Future<PullResult> pull(int cursor) =>
      throw const SyncUnavailable('no backend configured');
}

/// Thrown when the server rejects the token (user must sign in again).
class SyncUnauthorized implements Exception {
  const SyncUnauthorized();
}

class SyncUnavailable implements Exception {
  const SyncUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'SyncUnavailable($reason)';
}
