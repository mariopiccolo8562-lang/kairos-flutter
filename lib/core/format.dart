String _two(int n) => n.toString().padLeft(2, '0');

/// 1:05:09 oppure 05:09
String formatDuration(Duration d) {
  final value = d.isNegative ? Duration.zero : d;
  final h = value.inHours;
  final m = _two(value.inMinutes.remainder(60));
  final s = _two(value.inSeconds.remainder(60));
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// 21:30
String formatClock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// 05/11/2026
String formatDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

/// 1h 52min oppure 45min (vuoto se la durata non è nota)
String formatRuntime(int? seconds) {
  if (seconds == null || seconds <= 0) return '';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return h > 0 ? '${h}h ${m}min' : '${m}min';
}
