import 'dart:typed_data';

/// A local table that syncs as JSON documents (teams, members, audio…).
///
/// Same rules as matches/events: rows carry a revision and a sync status;
/// a row is marked synced only if the server stored that exact revision;
/// remote changes never overwrite a local pending change.
abstract class DocSyncSource {
  /// Key in the push/pull payload ('teams', 'members', 'audio').
  String get key;

  /// Max documents per push (smaller for heavy docs).
  int get batchSize => 100;

  Future<List<Map<String, dynamic>>> pending({required int limit});
  Future<void> markSynced(Map<String, int> accepted);

  /// Returns how many rows changed.
  Future<int> applyRemote(List<Map<String, dynamic>> docs);
}

/// A source whose documents have a binary file stored apart (audio).
abstract class BlobDocSource implements DocSyncSource {
  /// Bytes to upload before the document of [id] (null = no file).
  Future<({Uint8List bytes, String mimeType})?> blobFor(String id);

  /// Ids of remote documents whose file is not on this device yet.
  Future<List<String>> missingBlobs({int limit = 10});
  Future<void> saveBlob(String id, Uint8List bytes);
}
