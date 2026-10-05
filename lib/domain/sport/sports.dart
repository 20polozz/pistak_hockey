import 'roller_hockey.dart';
import 'sport_definition.dart';

/// Registry of supported sports. Future: futsal, basketball, handball...
abstract final class Sports {
  static const all = <SportDefinition>[rollerHockey];
  static const defaultSport = rollerHockey;

  static SportDefinition byId(String id) =>
      all.firstWhere((s) => s.id == id, orElse: () => defaultSport);
}
