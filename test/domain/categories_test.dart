import 'package:flutter_test/flutter_test.dart';
import 'package:pistak/domain/sport/roller_hockey.dart';

void main() {
  test('Catalan roller hockey categories (periods × minutes)', () {
    final got = {
      for (final f in rollerHockey.defaultFormats)
        f.name: (f.periods, f.periodDuration.inMinutes)
    };
    expect(got, {
      'Nacional Catalana masculina': (2, 25),
      'Nacional Catalana femenina': (2, 25),
      'Primera Catalana masculina': (2, 25),
      'Primera Catalana femenina': (2, 25),
      'Segona Catalana masculina': (2, 25),
      'Segona Catalana femenina': (2, 25),
      'Tercera Catalana masculina': (2, 25),
      'Fem 19': (2, 25),
      'Fem 17': (2, 20),
      'Fem 15': (2, 20),
      'Fem 13': (2, 20),
      'Fem 11': (2, 18),
      'Minifem': (4, 8),
      'Júnior': (2, 25),
      'Juvenil': (2, 20),
      'Infantil': (2, 20),
      'Aleví': (2, 20),
      'Benjamí': (2, 18),
      'Prebenjamí': (4, 8),
      'Veterans': (2, 25),
    });
    // Unique ids (stored inside every match).
    final ids = rollerHockey.defaultFormats.map((f) => f.id).toSet();
    expect(ids.length, rollerHockey.defaultFormats.length);
    // 4-part mini categories: clock math still correct.
    final mini =
        rollerHockey.defaultFormats.firstWhere((f) => f.name == 'Minifem');
    expect(mini.startOf(4), const Duration(minutes: 24));
    expect(mini.foulLimit, isNull);
  });
}
