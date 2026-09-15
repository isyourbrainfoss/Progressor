import 'dart:math' show min;

import '../models/force_sample.dart';

/// Merge one or more force streams into a single time-sorted series.
///
/// Drops consecutive duplicates (same [ForceSample.timeMs] and force). When
/// [preferDeviceTimestamps] is true, samples that carry [ForceSample.rawTimestampUs]
/// are rebased from the earliest device timestamp (µs → ms).
List<ForceSample> mergeSampleStreams(
  Iterable<Iterable<ForceSample>> streams, {
  bool preferDeviceTimestamps = false,
}) {
  final all = <ForceSample>[
    for (final stream in streams)
      for (final s in stream) s,
  ];
  if (all.isEmpty) return const [];

  var mapped = all;
  if (preferDeviceTimestamps) {
    final withUs = all.where((s) => s.rawTimestampUs != null).toList();
    if (withUs.isNotEmpty) {
      final minUs =
          withUs.map((s) => s.rawTimestampUs!).reduce((a, b) => min(a, b));
      mapped = [
        for (final s in all)
          s.rawTimestampUs == null
              ? s
              : s.copyWith(
                  timeMs: ((s.rawTimestampUs! - minUs) / 1000).round(),
                ),
      ];
    }
  }

  mapped.sort((a, b) {
    final c = a.timeMs.compareTo(b.timeMs);
    if (c != 0) return c;
    return a.forceKg.compareTo(b.forceKg);
  });

  final out = <ForceSample>[];
  for (final s in mapped) {
    if (out.isEmpty ||
        out.last.timeMs != s.timeMs ||
        out.last.forceKg != s.forceKg) {
      out.add(s);
    }
  }
  return out;
}
