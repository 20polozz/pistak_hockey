import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Password hashing with PBKDF2-HMAC-SHA256 (no plain-text passwords ever).
/// Format: `pbkdf2-sha256$<iterations>$<salt b64>$<hash b64>`
class PasswordHasher {
  PasswordHasher({this.iterations = 120000, Random? random})
      : _random = random ?? Random.secure();

  final int iterations;
  final Random _random;

  String hash(String password) {
    final salt = Uint8List.fromList(List.generate(16, (_) => _random.nextInt(256)));
    final dk = _pbkdf2(utf8.encode(password), salt, iterations, 32);
    return 'pbkdf2-sha256\$$iterations\$${base64.encode(salt)}\$${base64.encode(dk)}';
  }

  bool verify(String password, String stored) {
    final parts = stored.split(r'$');
    if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') return false;
    final iters = int.tryParse(parts[1]);
    if (iters == null) return false;
    final salt = base64.decode(parts[2]);
    final expected = base64.decode(parts[3]);
    final dk = _pbkdf2(utf8.encode(password), salt, iters, expected.length);
    return constantTimeEquals(dk, expected);
  }

  static Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations, int length) {
    final hmac = Hmac(sha256, password);
    final out = BytesBuilder();
    var block = 1;
    while (out.length < length) {
      final b = ByteData(4)..setUint32(0, block);
      var u = hmac.convert([...salt, ...b.buffer.asUint8List()]).bytes;
      final t = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.add(t);
      block++;
    }
    return Uint8List.fromList(out.takeBytes().sublist(0, length));
  }
}

bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var r = 0;
  for (var i = 0; i < a.length; i++) {
    r |= a[i] ^ b[i];
  }
  return r == 0;
}

/// Minimal HS256 JSON Web Tokens (access tokens).
class Jwt {
  Jwt(this.secret, {this.ttl = const Duration(days: 30)}) {
    if (secret.length < 32) {
      throw ArgumentError('JWT secret must be at least 32 characters');
    }
  }

  final String secret;
  final Duration ttl;

  static String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
  static List<int> _unb64(String s) => base64Url.decode(base64Url.normalize(s));

  String issue(String userId, {DateTime? now}) {
    final t = (now ?? DateTime.now().toUtc());
    final header = _b64(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})));
    final payload = _b64(utf8.encode(jsonEncode({
      'sub': userId,
      'iat': t.millisecondsSinceEpoch ~/ 1000,
      'exp': t.add(ttl).millisecondsSinceEpoch ~/ 1000,
    })));
    final sig = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$header.$payload'));
    return '$header.$payload.${_b64(sig.bytes)}';
  }

  /// Returns the user id, or null if the token is invalid or expired.
  String? verify(String token, {DateTime? now}) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final header = jsonDecode(utf8.decode(_unb64(parts[0]))) as Map<String, dynamic>;
      if (header['alg'] != 'HS256') return null;
      final expected = Hmac(sha256, utf8.encode(secret))
          .convert(utf8.encode('${parts[0]}.${parts[1]}'))
          .bytes;
      if (!constantTimeEquals(expected, _unb64(parts[2]))) return null;
      final payload = jsonDecode(utf8.decode(_unb64(parts[1]))) as Map<String, dynamic>;
      final exp = payload['exp'] as int?;
      final nowS = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/ 1000;
      if (exp == null || exp < nowS) return null;
      return payload['sub'] as String?;
    } catch (_) {
      return null;
    }
  }
}
