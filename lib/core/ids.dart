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
