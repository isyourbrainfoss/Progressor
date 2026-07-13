import 'models/force_sample.dart';
import 'models/pull_test.dart';

/// Computes key metrics for a pull test.
class TestMetrics {
  final double? peakKg;
  final double? meanKg;
  final double? durationS;
  final double? rfdMax; // kg/s (max rate of force development)
  final double? timeToPeakMs;
  final double? cfEstimateKg; // rough critical force from data if repeaters-like

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

TestMetrics computeMetrics(List<ForceSample> samples) {
  if (samples.isEmpty) {
    return const TestMetrics();
  }

  final sorted = List<ForceSample>.from(samples)..sort((a, b) => a.timeMs.compareTo(b.timeMs));
  final first = sorted.first;
  final last = sorted.last;

  double peak = sorted.map((s) => s.forceKg).reduce((a, b) => a > b ? a : b);
  double sum = sorted.map((s) => s.forceKg).reduce((a, b) => a + b);
  double mean = sum / sorted.length;
  double durS = (last.timeMs - first.timeMs) / 1000.0;

  // RFD: max delta force / delta time (kg per second)
  double maxRfd = 0;
  int peakIdx = 0;
  for (int i = 1; i < sorted.length; i++) {
    final dt = (sorted[i].timeMs - sorted[i - 1].timeMs) / 1000.0;
    if (dt <= 0) continue;
    final df = sorted[i].forceKg - sorted[i - 1].forceKg;
    final rfd = df / dt;
    if (rfd > maxRfd) maxRfd = rfd;
  }

  // Time to peak
  double? timeToPeak;
  for (int i = 0; i < sorted.length; i++) {
    if ((sorted[i].forceKg - 0.1) >= peak * 0.95) {  // ~95% of peak
      timeToPeak = (sorted[i].timeMs - first.timeMs).toDouble();
      peakIdx = i;
      break;
    }
  }

  // Very rough CF estimate: for endurance style, take average of last 30% or min of late plateaus
  double? cfEst;
  if (durS > 10 && sorted.length > 20) {
    final lateStart = (sorted.length * 0.6).floor();
    final lateSamples = sorted.sublist(lateStart);
    if (lateSamples.isNotEmpty) {
      cfEst = lateSamples.map((s) => s.forceKg).reduce((a, b) => a + b) / lateSamples.length;
    }
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
}
