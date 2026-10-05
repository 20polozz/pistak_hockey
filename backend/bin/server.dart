import 'dart:io';

import 'package:pistak_server/pistak_server.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Environment:
///   PISTAK_JWT_SECRET   required, ≥ 32 chars (never commit it)
///   PISTAK_DB           SQLite file path (default: pistak.sqlite)
///   PORT                default 8080
///   PISTAK_ORIGINS      comma-separated allowed web origins (default *)
///   PISTAK_STT_API_KEY  optional: enables POST /transcribe (never commit it)
///   PISTAK_STT_URL      optional: OpenAI-compatible /audio/transcriptions URL
///   PISTAK_STT_MODEL    optional (default whisper-1)
Future<void> main() async {
  final secret = Platform.environment['PISTAK_JWT_SECRET'] ?? '';
  if (secret.length < 32) {
    stderr.writeln('PISTAK_JWT_SECRET must be set (>= 32 chars).');
    exit(64);
  }
  final store = SqliteStore(Platform.environment['PISTAK_DB'] ?? 'pistak.sqlite');
  final env = Platform.environment;
  final sttKey = env['PISTAK_STT_API_KEY'] ?? '';
  final stt = sttKey.isEmpty
      ? null
      : OpenAiCompatibleStt(
          apiKey: sttKey,
          endpoint: env['PISTAK_STT_URL'] ?? 'https://api.openai.com/v1/audio/transcriptions',
          model: env['PISTAK_STT_MODEL'] ?? 'whisper-1',
        );
  final api = PistakApi(
    stt: stt,
    store: store,
    jwt: Jwt(secret),
    allowedOrigins: (Platform.environment['PISTAK_ORIGINS'] ?? '*').split(','),
  );
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await io.serve(api.handler, InternetAddress.anyIPv4, port);
  stdout.writeln('PISTAK API listening on :${server.port}');
  stdout.writeln('Speech-to-Text: ${stt == null ? 'disabled' : 'enabled'}');

  // Test harness mode: exit when the parent process goes away (stdin closes),
  // so no orphan server is ever left running.
  if (Platform.environment['PISTAK_EXIT_ON_STDIN_CLOSE'] == '1') {
    stdin.listen((_) {}, onDone: () async {
      await server.close(force: true);
      store.close();
      exit(0);
    });
  }
}
