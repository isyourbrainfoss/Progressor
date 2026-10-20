import 'models/force_sample.dart';
import 'models/pull_test.dart';

/// Window used for peak rate-of-force-development (kg/s).
///
/// Raw sample-to-sample derivatives at 80 Hz are dominated by sensor noise
/// (±0.2 kg over 12.5 ms is already ±30 kg/s) so RFD is measured as the
/// steepest rise over a short fixed window instead.
const int kRfdWindowMs = 50;

/// Force (kg) above which a pull is considered "on" for onset / mean-under-load.
/// Max of an absolute floor and a fraction of the session peak.
const double kLoadedFloorKg = 2.0;
const double kLoadedPeakFraction = 0.10;

/// Computes key metrics for a pull test.
class TestMetrics {
  final double? peakKg;

  /// Mean force while loaded (samples above the loaded threshold), so idle
  /// time before/after the pull and rests between repeaters don't drag it down.
  final double? meanKg;
  final double? durationS;
  final double? rfdMax; // kg/s (max rate of force development)
  final double? timeToPeakMs;
  final double?
  cfEstimateKg; // rough critical force from data if repeaters-like

  const TestMetrics({
    this.peakKg,
    this.meanKg,
    this.durationS,
    this.rfdMax,
    this.timeToPeakMs,
    this.cfEstimateKg,
  });

  Map<String, dynamic> toJson() => {
    'peakKg': peakKg,
    'meanKg': meanKg,
    'durationS': durationS,
    'rfdMax': rfdMax,
    'timeToPeakMs': timeToPeakMs,
    'cfEstimateKg': cfEstimateKg,
  };

  factory TestMetrics.fromJson(Map<String, dynamic> json) => TestMetrics(
    peakKg: (json['peakKg'] as num?)?.toDouble(),
    meanKg: (json['meanKg'] as num?)?.toDouble(),
    durationS: (json['durationS'] as num?)?.toDouble(),
    rfdMax: (json['rfdMax'] as num?)?.toDouble(),
    timeToPeakMs: (json['timeToPeakMs'] as num?)?.toDouble(),
    cfEstimateKg: (json['cfEstimateKg'] as num?)?.toDouble(),
  );
}

/// Loaded-force threshold for a session with the given [peakKg].
double loadedThresholdKg(double peakKg) {
  final frac = peakKg * kLoadedPeakFraction;
  return frac > kLoadedFloorKg ? frac : kLoadedFloorKg;
}

/// Steepest force rise over [windowMs] (kg/s). Samples must be time-sorted.
///
/// For each sample i the slope to the first sample at least [windowMs] later is
/// used. Sparse data (gaps larger than the window) still yields a slope over
/// the actual gap.
double peakRfdKgPerS(List<ForceSample> sorted, {int windowMs = kRfdWindowMs}) {
  var best = 0.0;
  var j = 0;
  for (var i = 0; i < sorted.length; i++) {
    if (j <= i) j = i + 1;
    while (j < sorted.length &&
        sorted[j].timeMs - sorted[i].timeMs < windowMs) {
      j++;
    }
    if (j >= sorted.length) break;
    final dt = (sorted[j].timeMs - sorted[i].timeMs) / 1000.0;
    if (dt <= 0) continue;
    final rfd = (sorted[j].forceKg - sorted[i].forceKg) / dt;
    if (rfd > best) best = rfd;
  }
  return best;
}

TestMetrics computeMetrics(List<ForceSample> samples) {
  if (samples.isEmpty) {
    return const TestMetrics();
  }

  final sorted = List<ForceSample>.from(samples)
    ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
  final first = sorted.first;
  final last = sorted.last;

  var peak = sorted.first.forceKg;
  var peakIndex = 0;
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i].forceKg > peak) {
      peak = sorted[i].forceKg;
      peakIndex = i;
    }
  }
  final durS = (last.timeMs - first.timeMs) / 1000.0;

  // Mean under load (falls back to all samples when nothing is "loaded").
  final threshold = loadedThresholdKg(peak);
  var loadedSum = 0.0;
  var loadedCount = 0;
  for (final s in sorted) {
    if (s.forceKg >= threshold) {
      loadedSum += s.forceKg;
      loadedCount++;
    }
  }
  final mean = loadedCount > 0
      ? loadedSum / loadedCount
      : sorted.map((s) => s.forceKg).reduce((a, b) => a + b) / sorted.length;

  final maxRfd = peakRfdKgPerS(sorted);

  // Time to ~peak (95%) measured from pull onset of the pull that contains
  // the peak — not from the first sample, which includes idle/ready time.
  double? timeToPeak;
  var onset = peakIndex;
  while (onset > 0 && sorted[onset - 1].forceKg >= threshold) {
    onset--;
  }
  for (var i = onset; i <= peakIndex; i++) {
    if ((sorted[i].forceKg - 0.1) >= peak * 0.95) {
      timeToPeak = (sorted[i].timeMs - sorted[onset].timeMs).toDouble();
      break;
    }
  }

  // Very rough CF estimate for endurance/repeaters: mean loaded force over the
  // last 40% of the session (rest phases excluded).
  double? cfEst;
  if (durS > 10 && sorted.length > 20) {
    final lateFromMs = first.timeMs + (durS * 1000 * 0.6);
    var sum = 0.0;
    var n = 0;
    for (final s in sorted) {
      if (s.timeMs >= lateFromMs && s.forceKg >= threshold) {
        sum += s.forceKg;
        n++;
      }
    }
    if (n > 0) cfEst = sum / n;
  }

  return TestMetrics(
    peakKg: peak,
    meanKg: mean,
    durationS: durS,
    rfdMax: maxRfd > 0 ? maxRfd : null,
    timeToPeakMs: timeToPeak,
    cfEstimateKg: cfEst,
  );
}

extension PullTestMetrics on PullTest {
  TestMetrics get computedMetrics {
    if (metrics != null && metrics!.isNotEmpty) {
      try {
        return TestMetrics.fromJson(metrics!);
      } catch (_) {}
    }
    return computeMetrics(samples);
  }

  /// Recorded with the simulated demo Progressor (excluded from PRs, streaks).
  bool get isDemo => metrics?['source'] == 'demo';
}
