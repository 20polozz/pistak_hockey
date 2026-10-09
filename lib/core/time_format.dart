/// Formats a duration as mm:ss (minutes may exceed 59, e.g. 50:00).
String formatMatchTime(Duration d) {
  final totalSeconds = d.isNegative ? 0 : d.inSeconds;
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// Parses "mm:ss" (or "m:ss", or plain minutes "12") into a duration.
/// Returns null if the text is not a valid time.
Duration? parseMatchTime(String text) {
  final t = text.trim();
  final match = RegExp(r'^(\d{1,3})(?::(\d{1,2}))?$').firstMatch(t);
  if (match == null) return null;
  final minutes = int.parse(match.group(1)!);
  final seconds = match.group(2) == null ? 0 : int.parse(match.group(2)!);
  if (seconds > 59) return null;
  return Duration(minutes: minutes, seconds: seconds);
}

/// Formats a local wall-clock time as HH:mm.
String formatClockTime(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// Formats a local date as dd/MM/yyyy.
String formatDate(DateTime t) {
  final l = t.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
}

/// Short timeout length as said in a pavilion: 1', 30'', 1'30''.
String formatTimeoutLength(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  if (m == 0) return "$s''";
  return s == 0 ? "$m'" : "$m'$s''";
}
