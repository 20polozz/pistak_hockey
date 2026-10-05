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
}

class SyncUnavailable implements Exception {
  const SyncUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'SyncUnavailable($reason)';
}
