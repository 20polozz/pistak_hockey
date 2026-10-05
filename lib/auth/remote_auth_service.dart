import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'token_store.dart';

/// Error codes returned by the API (localized in the UI).
class AuthError implements Exception {
  const AuthError(this.code);
  final String code; // invalid_credentials, email_taken, weak_password,
  // invalid_email, too_many_attempts, network
  @override
  String toString() => 'AuthError($code)';
}

/// Email + password account on the PISTAK API. Signing in is optional: the
/// app records matches without it; an account only adds cloud sync.
class RemoteAuthService extends ChangeNotifier implements AuthService {
  RemoteAuthService({
    required this.baseUrl,
    required this.store,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final TokenStore store;
  final http.Client _client;

  static const _kToken = 'pistak_token';
  static const _kUser = 'pistak_user';
  static const _kEmail = 'pistak_email';

  String? _token;
  String? _userId;
  String? _email;

  @override
  String? get currentUserId => _userId;
  @override
  bool get isSignedIn => _userId != null && _token != null;
  String? get email => _email;

  @override
  Future<String?> accessToken() async => _token;

  /// Restores a previous session (no network needed).
  Future<void> load() async {
    _token = await store.read(_kToken);
    _userId = await store.read(_kUser);
    _email = await store.read(_kEmail);
    notifyListeners();
  }

  Future<void> signIn(String email, String password) =>
      _auth('/auth/login', email, password);

  Future<void> register(String email, String password) =>
      _auth('/auth/register', email, password);

  Future<void> _auth(String path, String email, String password) async {
    final http.Response res;
    try {
      res = await _client
          .post(Uri.parse('$baseUrl$path'),
              headers: {'content-type': 'application/json'},
              body: jsonEncode({'email': email.trim(), 'password': password}))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const AuthError('network');
    }
    final body = res.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw AuthError(body['error'] as String? ?? 'network');
    }
    _token = body['token'] as String;
    _userId = body['userId'] as String;
    _email = body['email'] as String?;
    await store.write(_kToken, _token!);
    await store.write(_kUser, _userId!);
    if (_email != null) await store.write(_kEmail, _email!);
    notifyListeners();
  }

  /// Signs out on this device. Local matches stay on the device.
  Future<void> signOut() async {
    _token = null;
    _userId = null;
    _email = null;
    await store.delete(_kToken);
    await store.delete(_kUser);
    await store.delete(_kEmail);
    notifyListeners();
  }
}
