import 'package:uuid/uuid.dart';

/// Generates globally unique, time-ordered identifiers (UUID v7).
abstract class IdGenerator {
  String newId();
}

class UuidV7Generator implements IdGenerator {
  const UuidV7Generator();
  static const _uuid = Uuid();

  @override
  String newId() => _uuid.v7();
}

/// Deterministic ids for tests.
class SequentialIdGenerator implements IdGenerator {
  SequentialIdGenerator([this.prefix = 'id']);
  final String prefix;
  int _n = 0;

  @override
  String newId() => '$prefix-${(++_n).toString().padLeft(6, '0')}';
}

/// Deterministic ids derived from an external command id (e.g. a tap on the
/// watch). Replaying the same command produces the same event ids, so a
/// re-delivered command can never create duplicates.
class DerivedIdGenerator implements IdGenerator {
  DerivedIdGenerator(this.seed);
  final String seed;
  static const _uuid = Uuid();
  int _n = 0;

  @override
  String newId() => _uuid.v5(Namespace.url.value, 'pistak:$seed/${_n++}');

  /// The first ids a generator for [seed] returns (enough to cover the
  /// action id and the events of any single action).
  static Set<String> firstIds(String seed, [int count = 8]) {
    final g = DerivedIdGenerator(seed);
    return {for (var i = 0; i < count; i++) g.newId()};
  }
}
