import '../../domain/repositories/audio_repository.dart';
import 'transcription_service.dart';

class TranscriptionReport {
  const TranscriptionReport({this.done = 0, this.errors = 0, this.skipped = false});
  final int done;
  final int errors;
  final bool skipped;
}

/// Processes pending voice incidents in the background. It never blocks the
/// match: recording an incident only stores audio; this runs later, when a
/// service and connection are available.
class TranscriptionQueue {
  TranscriptionQueue({
    required this.audio,
    required this.service,
    this.languageCode,
  });

  final AudioRepository audio;
  final TranscriptionService service;
  String? languageCode;
  Future<TranscriptionReport>? _running;

  Future<TranscriptionReport> processPending() =>
      _running ??= _run().whenComplete(() => _running = null);

  Future<TranscriptionReport> _run() async {
    if (!await service.isAvailable()) {
      return const TranscriptionReport(skipped: true);
    }
    var done = 0;
    var errors = 0;
    for (final r in await audio.pendingTranscriptions()) {
      final full = await audio.get(r.id);
      final bytes = full?.bytes;
      if (full == null || bytes == null) continue;
      try {
        final text = await service.transcribe(bytes,
            mimeType: full.mimeType, languageCode: languageCode);
        await audio.saveTranscript(r.id, text.trim());
        done++;
      } on TranscriptionUnavailable {
        // Connection lost mid-way: leave everything pending, retry later.
        break;
      } catch (e) {
        errors++;
        await audio.markTranscriptionError(r.id, '$e');
      }
    }
    return TranscriptionReport(done: done, errors: errors);
  }
}
