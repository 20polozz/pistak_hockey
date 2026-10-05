import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

class UserRecord {
  const UserRecord(this.id, this.email, this.passwordHash);
  final String id;
  final String email;
  final String passwordHash;
}

/// Result of an upsert: the stored revision, or a rejection.
class UpsertResult {
  const UpsertResult.accepted(this.revision) : rejected = null;
  const UpsertResult.rejected(this.rejected) : revision = null;
  final int? revision;
  final String? rejected;
}

/// Storage boundary. SQLite implementation below; a PostgreSQL one can
/// implement the same interface without touching routes or clients.
abstract class Store {
  UserRecord? userByEmail(String email);
  UserRecord createUser(String id, String email, String passwordHash);

  /// kind: 'match' | 'event' | 'team' | 'member' | 'audio'. Idempotent: same id + lower/equal revision is
  /// a no-op that still reports the stored revision.
  UpsertResult upsert(String kind, String ownerId, Map<String, dynamic> doc);

  /// Changes for [ownerId] with server sequence > [since], grouped by kind.
  ({Map<String, List<Map<String, dynamic>>> byKind, int cursor}) changesSince(
      String ownerId, int since,
      {int limit = 500});

  /// Audio bytes of voice incidents (kept apart from the JSON documents).
  /// Returns false if the id belongs to another user.
  bool putBlob(String id, String ownerId, String mime, Uint8List bytes);
  ({String mime, Uint8List bytes})? getBlob(String id, String ownerId);
  void deleteBlob(String id, String ownerId);

  int count(String kind);
  void close();
}

class SqliteStore implements Store {
  SqliteStore(String path) : _db = path == ':memory:' ? sqlite3.openInMemory() : sqlite3.open(path) {
    _db.execute('PRAGMA journal_mode = WAL;');
    _db.execute('PRAGMA synchronous = FULL;');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS users(
        id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL,
        created_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS docs(
        kind TEXT NOT NULL, id TEXT NOT NULL, owner_id TEXT NOT NULL,
        revision INTEGER NOT NULL, payload TEXT NOT NULL,
        server_seq INTEGER NOT NULL, updated_at INTEGER NOT NULL,
        PRIMARY KEY(kind, id));
      CREATE INDEX IF NOT EXISTS idx_docs_owner_seq ON docs(owner_id, server_seq);
      CREATE TABLE IF NOT EXISTS seq(id INTEGER PRIMARY KEY CHECK (id = 1), value INTEGER NOT NULL);
      INSERT OR IGNORE INTO seq(id, value) VALUES (1, 0);
      CREATE TABLE IF NOT EXISTS blobs(
        id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, mime TEXT NOT NULL,
        bytes BLOB NOT NULL, updated_at INTEGER NOT NULL);
    ''');
  }

  final Database _db;

  @override
  UserRecord? userByEmail(String email) {
    final r = _db.select('SELECT id, email, password_hash FROM users WHERE email = ?', [email]);
    if (r.isEmpty) return null;
    return UserRecord(r.first['id'] as String, r.first['email'] as String, r.first['password_hash'] as String);
  }

  @override
  UserRecord createUser(String id, String email, String passwordHash) {
    _db.execute('INSERT INTO users(id, email, password_hash, created_at) VALUES (?, ?, ?, ?)',
        [id, email, passwordHash, DateTime.now().millisecondsSinceEpoch]);
    return UserRecord(id, email, passwordHash);
  }

  int _nextSeq() {
    _db.execute('UPDATE seq SET value = value + 1 WHERE id = 1');
    return _db.select('SELECT value FROM seq WHERE id = 1').first['value'] as int;
  }

  @override
  UpsertResult upsert(String kind, String ownerId, Map<String, dynamic> doc) {
    final id = doc['id'];
    final rev = doc['revision'];
    if (id is! String || id.isEmpty || rev is! int || rev < 1) {
      return const UpsertResult.rejected('invalid document');
    }
    _db.execute('BEGIN IMMEDIATE');
    try {
      final cur = _db.select('SELECT owner_id, revision FROM docs WHERE kind = ? AND id = ?', [kind, id]);
      if (cur.isNotEmpty) {
        if (cur.first['owner_id'] != ownerId) {
          _db.execute('ROLLBACK');
          return const UpsertResult.rejected('forbidden');
        }
        final stored = cur.first['revision'] as int;
        if (rev <= stored) {
          _db.execute('COMMIT');
          return UpsertResult.accepted(stored);
        }
        _db.execute(
            'UPDATE docs SET revision = ?, payload = ?, server_seq = ?, updated_at = ? WHERE kind = ? AND id = ?',
            [rev, jsonEncode(doc), _nextSeq(), DateTime.now().millisecondsSinceEpoch, kind, id]);
      } else {
        _db.execute(
            'INSERT INTO docs(kind, id, owner_id, revision, payload, server_seq, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [kind, id, ownerId, rev, jsonEncode(doc), _nextSeq(), DateTime.now().millisecondsSinceEpoch]);
      }
      _db.execute('COMMIT');
      return UpsertResult.accepted(rev);
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  ({Map<String, List<Map<String, dynamic>>> byKind, int cursor}) changesSince(
      String ownerId, int since,
      {int limit = 500}) {
    final rows = _db.select(
        'SELECT kind, payload, server_seq FROM docs WHERE owner_id = ? AND server_seq > ? ORDER BY server_seq LIMIT ?',
        [ownerId, since, limit]);
    final byKind = <String, List<Map<String, dynamic>>>{};
    var cursor = since;
    for (final r in rows) {
      final doc = jsonDecode(r['payload'] as String) as Map<String, dynamic>;
      (byKind[r['kind'] as String] ??= []).add(doc);
      cursor = r['server_seq'] as int;
    }
    return (byKind: byKind, cursor: cursor);
  }

  @override
  bool putBlob(String id, String ownerId, String mime, Uint8List bytes) {
    final cur = _db.select('SELECT owner_id FROM blobs WHERE id = ?', [id]);
    if (cur.isNotEmpty && cur.first['owner_id'] != ownerId) return false;
    _db.execute(
        'INSERT INTO blobs(id, owner_id, mime, bytes, updated_at) VALUES (?, ?, ?, ?, ?) '
        'ON CONFLICT(id) DO UPDATE SET mime = excluded.mime, bytes = excluded.bytes, updated_at = excluded.updated_at',
        [id, ownerId, mime, bytes, DateTime.now().millisecondsSinceEpoch]);
    return true;
  }

  @override
  ({String mime, Uint8List bytes})? getBlob(String id, String ownerId) {
    final r = _db.select('SELECT mime, bytes FROM blobs WHERE id = ? AND owner_id = ?', [id, ownerId]);
    if (r.isEmpty) return null;
    return (mime: r.first['mime'] as String, bytes: r.first['bytes'] as Uint8List);
  }

  @override
  void deleteBlob(String id, String ownerId) =>
      _db.execute('DELETE FROM blobs WHERE id = ? AND owner_id = ?', [id, ownerId]);

  @override
  int count(String kind) =>
      _db.select('SELECT COUNT(*) AS c FROM docs WHERE kind = ?', [kind]).first['c'] as int;

  @override
  void close() => _db.close();
}
