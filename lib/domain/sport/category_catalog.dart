import 'match_format.dart';

/// The categories the user sees: built-in ones (with the user's changes
/// applied) followed by the user's own.
///
/// A stored category whose id equals a built-in id is an OVERRIDE of that
/// built-in (edited durations, breaks…); any other stored id is custom.
class CategoryCatalog {
  CategoryCatalog(this.builtIn, List<MatchFormat> stored)
      : _stored = {for (final f in stored) f.id: f};

  final List<MatchFormat> builtIn;
  final Map<String, MatchFormat> _stored;

  late final Set<String> builtInIds = {for (final f in builtIn) f.id};

  List<MatchFormat> get all => [
        for (final f in builtIn) _stored[f.id] ?? f,
        for (final f in _stored.values)
          if (!builtInIds.contains(f.id)) f,
      ];

  bool isBuiltIn(String id) => builtInIds.contains(id);

  /// A built-in the user changed (can be restored).
  bool isModified(String id) => isBuiltIn(id) && _stored.containsKey(id);

  MatchFormat? original(String id) =>
      builtIn.where((f) => f.id == id).firstOrNull;

  MatchFormat? byId(String id) => all.where((f) => f.id == id).firstOrNull;

  /// Looks a category up by its (case-insensitive) name.
  MatchFormat? byName(String? name) {
    final n = name?.trim().toLowerCase();
    if (n == null || n.isEmpty) return null;
    return all.where((f) => f.name.toLowerCase() == n).firstOrNull;
  }
}

/// Seasons offered in pickers ("26/27" … "30/31").
const seasonOptions = ['26/27', '27/28', '28/29', '29/30', '30/31'];
