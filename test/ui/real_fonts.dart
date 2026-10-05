import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the real Roboto + Material Icons from the Flutter SDK so layout
/// tests measure text like a device does (the default test font draws every
/// glyph as a full square, which exaggerates widths a lot).
Future<void> loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = Directory([root, 'bin', 'cache', 'artifacts', 'material_fonts']
      .join(Platform.pathSeparator));
  if (!dir.existsSync()) return;
  final roboto = FontLoader('Roboto');
  final icons = FontLoader('MaterialIcons');
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    final data = f.readAsBytes().then((b) => ByteData.sublistView(b));
    if (name.startsWith('Roboto-') && !name.contains('Mono')) {
      roboto.addFont(data);
    } else if (name.startsWith('MaterialIcons-Regular')) {
      icons.addFont(data);
    }
  }
  await roboto.load();
  final poppins = FontLoader('Poppins')
    ..addFont(File('assets/fonts/Poppins-Bold.ttf')
        .readAsBytes()
        .then((b) => ByteData.sublistView(b)));
  await poppins.load();
  await icons.load();
}
