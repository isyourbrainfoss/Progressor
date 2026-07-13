import 'package:meta/meta.dart';

/// A single force reading from the sensor.
@immutable
class ForceSample {
  const ForceSample({
    required this.timeMs,
    required this.forceKg,
    this.forceN,
    this.rawTimestampUs,
  });

  final int timeMs; // relative monotonic ms from start of recording
  final double forceKg;
  final double? forceN;
  final int? rawTimestampUs;

  double get forceNewtons => forceN ?? forceKg * 9.80665;

  ForceSample copyWith({int? timeMs, double? forceKg, double? forceN, int? rawTimestampUs}) {
    return ForceSample(
      timeMs: timeMs ?? this.timeMs,
      forceKg: forceKg ?? this.forceKg,
      forceN: forceN ?? this.forceN,
      rawTimestampUs: rawTimestampUs ?? this.rawTimestampUs,
    );
  }

  Map<String, dynamic> toJson() => {
        'timeMs': timeMs,
        'forceKg': forceKg,
        'forceN': forceN,
        'rawTimestampUs': rawTimestampUs,
      };

  factory ForceSample.fromJson(Map<String, dynamic> json) => ForceSample(
        timeMs: json['timeMs'] as int,
        forceKg: (json['forceKg'] as num).toDouble(),
        forceN: (json['forceN'] as num?)?.toDouble(),
        rawTimestampUs: json['rawTimestampUs'] as int?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForceSample &&
          runtimeType == other.runtimeType &&
          timeMs == other.timeMs &&
          forceKg == other.forceKg;

  @override
  int get hashCode => timeMs.hashCode ^ forceKg.hashCode;
}
