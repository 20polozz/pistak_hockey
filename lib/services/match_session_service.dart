import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Device integrations used while recording a match.
class MatchSessionService {
  const MatchSessionService();

  /// Keeps the screen on during a match (best effort, never throws).
  Future<void> keepScreenOn(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (_) {}
  }

  /// Immediate tactile confirmation of a tap.
  void tap() {
    HapticFeedback.mediumImpact();
  }

  void heavy() {
    HapticFeedback.heavyImpact();
  }
}
