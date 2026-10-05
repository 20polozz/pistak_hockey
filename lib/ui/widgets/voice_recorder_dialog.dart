import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../l10n/app_localizations.dart';
import '../../services/audio/audio_capture_service.dart';

/// Result of the recorder: audio, or the reason it could not be recorded.
class VoiceRecorderResult {
  const VoiceRecorderResult.audio(CapturedAudio this.audio) : error = null;
  const VoiceRecorderResult.error(Object this.error) : audio = null;
  final CapturedAudio? audio;
  final Object? error;
}

/// Full-screen-ish dialog: starts recording immediately, one big STOP button.
class VoiceRecorderDialog extends StatefulWidget {
  const VoiceRecorderDialog({super.key});

  static Future<VoiceRecorderResult?> show(BuildContext context) =>
      showDialog<VoiceRecorderResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const VoiceRecorderDialog(),
      );

  @override
  State<VoiceRecorderDialog> createState() => _VoiceRecorderDialogState();
}

class _VoiceRecorderDialogState extends State<VoiceRecorderDialog> {
  final _capture = AudioCaptureService();
  final _watch = Stopwatch();
  Timer? _ticker;
  bool _started = false;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await _capture.start();
      _watch.start();
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) setState(() {});
      });
      if (mounted) setState(() => _started = true);
    } catch (e) {
      if (mounted) Navigator.pop(context, VoiceRecorderResult.error(e));
    }
  }

  Future<void> _stop() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    _ticker?.cancel();
    try {
      final audio = await _capture.stop();
      if (mounted) Navigator.pop(context, VoiceRecorderResult.audio(audio));
    } catch (e) {
      if (mounted) Navigator.pop(context, VoiceRecorderResult.error(e));
    }
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    await _capture.cancel();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_capture.isRecording) _capture.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.incidentVoice),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic,
              size: 64,
              color: _started ? PistakColors.danger : PistakColors.textMuted),
          const SizedBox(height: 8),
          Text(_started ? l.recording : '…',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(
            formatMatchTime(_watch.elapsed),
            style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                fontFeatures: tabularFigures),
          ),
          const SizedBox(height: 12),
          Text(l.micPrivacy,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 12, color: PistakColors.textMuted)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: PistakColors.danger,
                  foregroundColor: Colors.white),
              onPressed: _started && !_stopping ? _stop : null,
              icon: const Icon(Icons.stop),
              label: Text(l.stopAndSave),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _stopping ? null : _cancel, child: Text(l.cancel)),
      ],
    );
  }
}
