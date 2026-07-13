import '../metrics.dart';
import '../models/pull_test.dart';

String exportTestToCsv(PullTest test) {
  final buf = StringBuffer();
  buf.writeln('time_ms,force_kg');
  for (final s in test.samples) {
    buf.writeln('${s.timeMs},${s.forceKg}');
  }
  return buf.toString();
}

String exportAllToCsv(List<PullTest> tests) {
  final buf = StringBuffer();
  buf.writeln('id,start_iso,type,peak_kg,duration_s');
  for (final t in tests) {
    final m = computeMetrics(t.samples);
    buf.writeln('${t.id},${t.startTime.toIso8601String()},${t.type.name},${m.peakKg ?? ""},${m.durationS ?? ""}');
  }
  return buf.toString();
}
