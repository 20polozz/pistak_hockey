import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/clock.dart';
import '../domain/repositories/match_repository.dart';
import '../ui/match_controller.dart';
import 'wear_commands.dart';

/// Phone side of the Wear OS link (Android only).
///
/// The native WearableListenerService writes every command received from the
/// watch to a durable inbox file and acknowledges it to the watch. This class
/// drains that inbox: each command is applied (idempotently) and only THEN
/// removed from the inbox, so a crash in between just replays it.
class WearBridge {
  WearBridge({
    required this.repository,
    required this.controllerFor,
    required this.clock,
    MethodChannel? channel,
  })  : _channel = channel ?? const MethodChannel('pistak/wear'),
        processor = WearCommandProcessor(
            repository: repository, controllerFor: controllerFor, clock: clock);

  final MatchRepository repository;
  final MatchController Function(String matchId) controllerFor;
  final Clock clock;
  final WearCommandProcessor processor;
  final MethodChannel _channel;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Timer? _poll;
  StreamSubscription<Object?>? _sub;
  Future<void> _draining = Future<void>.value();
  bool _started = false;

  void start() {
    if (!supported || _started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'inboxChanged') drain().ignore();
      return null;
    });
    drain().ignore();
    var ticks = 0;
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      drain().ignore();
      // A watch that connects later still gets the scoreboard.
      if (++ticks % 10 == 0 && _lastState != null) _send(_lastState!);
    });
    _sub = repository.watchActiveMatch().listen((m) async {
      try {
        final state =
            m == null ? null : await controllerFor(m.id).currentState();
        _lastState = jsonEncode(wearScoreState(state, clock.now()));
        await _send(_lastState!);
      } on Object catch (e) {
        debugPrint('wear: state failed: $e');
      }
    });
  }

  String? _lastState;

  Future<void> _send(String json) async {
    try {
      await _channel.invokeMethod<void>('sendState', json);
    } on Object catch (e) {
      debugPrint('wear: sendState failed: $e');
    }
  }

  /// Serialised: never two drains at the same time.
  Future<void> drain() => _draining = _draining.then((_) => _drainOnce());

  Future<void> _drainOnce() async {
    try {
      final lines =
          await _channel.invokeListMethod<String>('readInbox') ?? const [];
      if (lines.isEmpty) return;
      final done = <String>[];
      for (final line in lines) {
        final cmd = WearCommand.tryParse(line);
        if (cmd == null) {
          done.add(line); // malformed: drop it
          continue;
        }
        await processor.process(cmd);
        done.add(line);
      }
      await _channel.invokeMethod<void>('removeFromInbox', done);
    } on MissingPluginException {
      // Not available on this build/device.
    } on Object catch (e) {
      debugPrint('wear: drain failed, will retry: $e');
    }
  }

  void dispose() {
    _poll?.cancel();
    _sub?.cancel();
  }
}
