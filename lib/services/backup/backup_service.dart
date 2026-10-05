import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../core/clock.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sync/drift_doc_sources.dart';
import '../../domain/repositories/match_repository.dart';

class BackupPasswordRequired implements Exception {
  const BackupPasswordRequired();
}

class BackupWrongPassword implements Exception {
  const BackupWrongPassword();
}

class BackupInvalid implements Exception {
  const BackupInvalid(this.reason);
  final String reason;
  @override
  String toString() => 'BackupInvalid($reason)';
}

class RestoreReport {
  const RestoreReport(
      {required this.matches, required this.events, required this.others});
  final int matches;
  final int events;
  final int others;
  int get total => matches + events + others;
}

/// Full backup of everything on this device in ONE file:
/// matches, events, teams, rosters, voice recordings and categories.
///
/// File = "PSTK" + version + flags [+ salt + nonce] + payload.
/// With a password the payload is AES-256-GCM encrypted, key derived with
/// PBKDF2-HMAC-SHA256 (a wrong password or a modified file is detected).
///
/// Restoring MERGES (never deletes): items are matched by id and the higher
/// revision wins; local unsynced edits are kept. Restoring twice is a no-op.
class BackupService {
  BackupService({
    required this.db,
    required this.matches,
    required this.settings,
    this.clock = const SystemClock(),
    this.appName = 'pistak. hockey',
    this.iterations = 120000,
  });

  final AppDatabase db;
  final MatchRepository matches;
  final SettingsRepository settings;
  final Clock clock;
  final String appName;
  final int iterations;

  static const _magic = [0x50, 0x53, 0x54, 0x4B]; // "PSTK"
  static const _version = 1;
  static const _flagEncrypted = 1;
  static const _settingsKeys = ['categories', 'last_format'];

  static bool isEncrypted(Uint8List file) =>
      file.length > 6 && _hasMagic(file) && (file[5] & _flagEncrypted) != 0;

  static bool _hasMagic(Uint8List f) =>
      f.length > 6 &&
      f[0] == _magic[0] &&
      f[1] == _magic[1] &&
      f[2] == _magic[2] &&
      f[3] == _magic[3];

  // ------------------------------------------------------------- export

  Future<Map<String, dynamic>> _collect() async {
    final infos = await matches.watchMatches().first;
    final events = <Map<String, dynamic>>[];
    for (final m in infos) {
      for (final e in await matches.getEvents(m.id)) {
        events.add(e.toJson());
      }
    }
    final audioSource = AudioDocSource(db);
    final audio = <Map<String, dynamic>>[];
    for (final doc in await audioSource.all()) {
      final blob = await audioSource.blobFor(doc['id'] as String);
      audio.add({...doc, if (blob != null) 'bytes': base64Encode(blob.bytes)});
    }
    return {
      'format': 'pistak-backup',
      'version': _version,
      'app': appName,
      'createdAt': clock.now().toUtc().toIso8601String(),
      'matches': [for (final m in infos) m.toJson()],
      'events': events,
      'teams': await TeamDocSource(db).all(),
      'members': await MemberDocSource(db).all(),
      'audio': audio,
      'settings': {
        for (final k in _settingsKeys)
          if (await settings.get(k) case final v?) k: v,
      },
    };
  }

  /// The backup file bytes. [password] null/empty = not encrypted.
  Future<Uint8List> export({String? password}) async {
    final payload =
        Uint8List.fromList(utf8.encode(jsonEncode(await _collect())));
    final out = BytesBuilder()
      ..add(_magic)
      ..addByte(_version);
    if (password == null || password.isEmpty) {
      out
        ..addByte(0)
        ..add(payload);
      return out.toBytes();
    }
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final key = await _deriveKey(password, salt);
    final box = await AesGcm.with256bits().encrypt(payload, secretKey: key);
    out
      ..addByte(_flagEncrypted)
      ..add(salt)
      ..add(box.nonce) // 12 bytes
      ..add(box.cipherText)
      ..add(box.mac.bytes); // 16 bytes
    return out.toBytes();
  }

  Future<SecretKey> _deriveKey(String password, List<int> salt) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
          .deriveKeyFromPassword(password: password, nonce: salt);

  // ------------------------------------------------------------ restore

  Future<Map<String, dynamic>> read(Uint8List file, {String? password}) async {
    if (!_hasMagic(file)) throw const BackupInvalid('not a pistak backup');
    if (file[4] > _version) throw const BackupInvalid('newer backup version');
    Uint8List payload;
    if ((file[5] & _flagEncrypted) != 0) {
      if (password == null || password.isEmpty) {
        throw const BackupPasswordRequired();
      }
      if (file.length < 6 + 16 + 12 + 16) throw const BackupInvalid('short');
      final salt = file.sublist(6, 22);
      final nonce = file.sublist(22, 34);
      final cipher = file.sublist(34, file.length - 16);
      final mac = Mac(file.sublist(file.length - 16));
      try {
        payload = Uint8List.fromList(await AesGcm.with256bits().decrypt(
            SecretBox(cipher, nonce: nonce, mac: mac),
            secretKey: await _deriveKey(password, salt)));
      } on SecretBoxAuthenticationError {
        throw const BackupWrongPassword();
      }
    } else {
      payload = file.sublist(6);
    }
    try {
      final data = jsonDecode(utf8.decode(payload));
      if (data is! Map<String, dynamic> || data['format'] != 'pistak-backup') {
        throw const BackupInvalid('unknown content');
      }
      return data;
    } on FormatException {
      throw const BackupInvalid('corrupted');
    }
  }

  Future<RestoreReport> restore(Uint8List file, {String? password}) async {
    final data = await read(file, password: password);
    List<Map<String, dynamic>> list(String k) => [
          for (final x in (data[k] as List? ?? const []))
            if (x is Map) Map<String, dynamic>.from(x)
        ];
    final ms = list('matches');
    final es = list('events');
    final changed = await matches.applyRemote(matches: ms, events: es);
    var others = 0;
    others += await TeamDocSource(db).applyRemote(list('teams'));
    others += await MemberDocSource(db).applyRemote(list('members'));
    final audioDocs = list('audio');
    final audioSource = AudioDocSource(db);
    others += await audioSource.applyRemote(audioDocs);
    for (final d in audioDocs) {
      final b = d['bytes'];
      if (b is String && d['id'] is String) {
        await audioSource.saveBlob(d['id'] as String, base64Decode(b));
      }
    }
    final st = data['settings'];
    if (st is Map) {
      for (final k in _settingsKeys) {
        final v = st[k];
        if (v is String && await settings.get(k) == null) {
          await settings.set(k, v);
        }
      }
    }
    return RestoreReport(
        matches: ms.length, events: es.length, others: others + changed * 0);
  }
}
