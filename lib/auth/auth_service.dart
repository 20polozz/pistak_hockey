/// Authentication boundary.
///
/// Phase 1: everyone is a guest and everything stays on the device.
/// Phase 2: a real implementation (backend auth, secure token storage) will
/// replace [GuestAuthService] without touching match code.
abstract class AuthService {
  /// Current user id, or null for a guest (no account).
  String? get currentUserId;
  bool get isSignedIn => currentUserId != null;

  /// Access token for the sync API (null if guest).
  Future<String?> accessToken();
}

class GuestAuthService implements AuthService {
  const GuestAuthService();

  @override
  String? get currentUserId => null;

  @override
  bool get isSignedIn => false;

  @override
  Future<String?> accessToken() async => null;
}
