import 'package:meta/meta.dart';
import 'force_sample.dart';
import 'test_type.dart';

/// A recorded test or training pull session.
@immutable
class PullTest {
  const PullTest({
    required this.id,
    required this.startTime,
    required this.type,
    required this.samples,
    this.endTime,
    this.gripType,
    this.hand,
    this.bodyweightKg,
    this.notes,
    this.deviceName,
    this.metrics,
  });

  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final TestType type;
  final List<ForceSample> samples;
  final String? gripType; // e.g. '20mm edge', '4 finger open', 'pocket'
  final String? hand; // 'left', 'right', 'both'
  final double? bodyweightKg;
  final String? notes;
  final String? deviceName;
  final Map<String, dynamic>? metrics; // computed: peak, avg, rfd, cf etc.

  double? get peakForceKg {
    if (samples.isEmpty) return null;
    return samples.map((s) => s.forceKg).reduce((a, b) => a > b ? a : b);
  }

  double? get durationS {
    if (samples.isEmpty) return null;
    return (samples.last.timeMs - samples.first.timeMs) / 1000.0;
  }

  PullTest copyWith({
    String? id,
    DateTime? startTime,
    DateTime? endTime,
    TestType? type,
    List<ForceSample>? samples,
    String? gripType,
    String? hand,
    double? bodyweightKg,
    String? notes,
    String? deviceName,
    Map<String, dynamic>? metrics,
  }) {
    return PullTest(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      type: type ?? this.type,
      samples: samples ?? this.samples,
      gripType: gripType ?? this.gripType,
      hand: hand ?? this.hand,
      bodyweightKg: bodyweightKg ?? this.bodyweightKg,
      notes: notes ?? this.notes,
      deviceName: deviceName ?? this.deviceName,
      metrics: metrics ?? this.metrics,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'type': type.name,
        'samples': samples.map((s) => s.toJson()).toList(),
        'gripType': gripType,
        'hand': hand,
        'bodyweightKg': bodyweightKg,
        'notes': notes,
        'deviceName': deviceName,
        'metrics': metrics,
      };

  factory PullTest.fromJson(Map<String, dynamic> json) {
    return PullTest(
      id: json['id'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      type: TestType.values.firstWhere((t) => t.name == json['type'], orElse: () => TestType.custom),
      samples: (json['samples'] as List).map((e) => ForceSample.fromJson(e as Map<String, dynamic>)).toList(),
      gripType: json['gripType'] as String?,
      hand: json['hand'] as String?,
      bodyweightKg: (json['bodyweightKg'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      deviceName: json['deviceName'] as String?,
      metrics: json['metrics'] as Map<String, dynamic>?,
    );
  }
}
