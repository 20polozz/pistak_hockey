import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/domain/sport/category_catalog.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';

void main() {
  test('built-ins can be edited and restored; customs are appended', () {
    final alevi =
        rollerHockey.defaultFormats.firstWhere((f) => f.name == 'Aleví');
    final edited = alevi.copyWith(periodDuration: const Duration(minutes: 22));
    final custom = alevi.copyWith(id: 'cat_x', name: 'Torneig estiu');
    final c = CategoryCatalog(rollerHockey.defaultFormats, [edited, custom]);

    expect(c.all.length, rollerHockey.defaultFormats.length + 1);
    expect(c.all.last.name, 'Torneig estiu');
    expect(c.byName('aleví')!.periodDuration, const Duration(minutes: 22));
    expect(c.isModified(alevi.id), isTrue);
    expect(c.isBuiltIn('cat_x'), isFalse);
    expect(c.original(alevi.id)!.periodDuration, const Duration(minutes: 20));
    // Position of the edited built-in doesn't move.
    expect(c.all.indexWhere((f) => f.id == alevi.id),
        rollerHockey.defaultFormats.indexOf(alevi));

    final restored = CategoryCatalog(rollerHockey.defaultFormats, [custom]);
    expect(
        restored.byName('Aleví')!.periodDuration, const Duration(minutes: 20));
    expect(seasonOptions, ['26/27', '27/28', '28/29', '29/30', '30/31']);
  });
}
