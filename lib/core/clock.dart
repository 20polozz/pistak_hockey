/// Source of "now". Injected everywhere so tests can control time.
///
/// All match timing is derived from wall-clock timestamps (UTC), never from
/// a ticking counter. See docs/ANALYSIS.md §10.
abstract class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// Manually driven clock for tests.
class FakeClock implements Clock {
  FakeClock(DateTime start) : _now = start.toUtc();

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration d) => _now = _now.add(d);

  void set(DateTime t) => _now = t.toUtc();
}

/// Always returns the same instant (used to stamp an action with the exact
/// moment of the tap, even if it is processed a few ms later).
class FixedClock implements Clock {
  FixedClock(DateTime at) : _at = at.toUtc();
  final DateTime _at;

  @override
  DateTime now() => _at;
}
