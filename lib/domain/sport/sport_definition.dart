import 'match_format.dart';

/// Describes a sport: which event types and card colours it uses and its
/// default formats. Adding a sport = adding a new [SportDefinition]; the
/// event log, clock and sync engine stay the same.
class SportDefinition {
  const SportDefinition({
    required this.id,
    required this.supportedEventTypes,
    required this.cardColors,
    required this.defaultFormats,
  });

  final String id;
  final Set<String> supportedEventTypes;

  /// Card colour codes in display order (e.g. yellow, blue, red).
  final List<String> cardColors;
  final List<MatchFormat> defaultFormats;

  MatchFormat get defaultFormat => defaultFormats.first;

  MatchFormat? formatById(String id) {
    for (final f in defaultFormats) {
      if (f.id == id) return f;
    }
    return null;
  }
}
