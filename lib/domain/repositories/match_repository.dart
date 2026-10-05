import '../match/match_event.dart';
import '../match/match_info.dart';
import '../sport/match_format.dart';

/// Local, offline-first storage of matches and their event log.
///
/// Every write is durable when the returned Future completes. Implementations
/// must never physically delete events: undo/delete = tombstone.
abstract class MatchRepository {
  // ----------------------------------------------------------- matches
  Future<MatchInfo> createMatch({
    required String sport,
    required MatchFormat format,
    String? homeName,
    String? awayName,
    String? homeTeamId,
    String? awayTeamId,
    String? category,
    String? competition,
    String? venue,
    String? season,
    String? notes,
    DateTime? scheduledAt,
  });

  Future<MatchInfo?> getMatch(String id);
  Stream<MatchInfo?> watchMatch(String id);

  /// All non-deleted matches, newest first.
  Stream<List<MatchInfo>> watchMatches();

  /// The most recent match that started and hasn't finished (for recovery).
  Stream<MatchInfo?> watchActiveMatch();

  /// Saves descriptive fields (teams, venue, format...). Bumps revision.
  Future<void> saveMatchDetails(MatchInfo info);

  /// Soft-deletes a match.
  Future<void> deleteMatch(String id);

  // ------------------------------------------------------------ events
  Future<List<MatchEvent>> getEvents(String matchId);
  Stream<List<MatchEvent>> watchEvents(String matchId);

  /// Appends the events of one action atomically (all or nothing) and
  /// refreshes the match cache (score/status) in the same transaction.
  /// Returns the stored events (with definitive seq).
  Future<List<MatchEvent>> appendEvents(
      String matchId, List<MatchEvent> events);

  /// Edits team / match time / metadata of an event. Bumps revision.
  Future<void> updateEvent(MatchEvent event);

  /// Undo: voids every event of the most recent non-voided action.
  /// Returns the voided events (empty if nothing to undo).
  Future<List<MatchEvent>> undoLastAction(String matchId);

  /// Voids or restores a single event.
  Future<void> setEventVoided(String eventId, {required bool voided});

  // -------------------------------------------------------------- sync
  Future<List<MatchEvent>> pendingEvents({int limit = 200});
  Future<List<MatchInfo>> pendingMatches({int limit = 50});

  /// Marks as synced only rows whose revision still equals the acked one.
  Future<void> markEventsSynced(Map<String, int> revisionsById);
  Future<void> markMatchesSynced(Map<String, int> revisionsById);

  Stream<int> watchPendingCount();

  /// Applies documents pulled from the server (other devices). A remote
  /// copy only replaces a local one with a LOWER revision that has no
  /// unsent local changes. Returns how many rows changed.
  Future<int> applyRemote({
    List<Map<String, dynamic>> matches = const [],
    List<Map<String, dynamic>> events = const [],
  });
}
