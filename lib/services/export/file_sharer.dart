import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Hands a generated file to the user: Android share sheet (save to Files,
/// Drive, WhatsApp, email…), Web Share API or a plain download on the web.
class FileSharer {
  const FileSharer();

  Future<void> share(Uint8List bytes,
      {required String fileName, required String mimeType}) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
      fileNameOverrides: [fileName],
      downloadFallbackEnabled: true,
    ));
  }
}

/// "CP Exemple - HC Exemple 2026-10-12" → safe file name.
String reportFileName(String title, DateTime date, String ext) {
  final d = date.toLocal();
  final day =
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final base = title
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
      .replaceAll(RegExp(r'\s+'), '_')
      .trim();
  return 'PISTAK_${base.isEmpty ? 'match' : base}_$day.$ext';
}
