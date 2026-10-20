import 'dart:math' as math;

import 'package:progressor_core/progressor_core.dart';

/// A virtual climber pulling on a simulated Progressor.
///
/// Physiology-flavoured but simple:
/// * **Intent** — a commanded force derived from what the app is asking for
///   (protocol type, phase, target) with a human reaction delay.
/// * **Muscle** — force follows the intent through a first-order lag with a
///   rate limit (finite rate of force development and release).
/// * **Fatigue** — a critical-force / W′ balance model: force above CF drains
///   W′, which lowers the achievable capacity; rest below CF recovers it.
///   This is what makes later repeaters sag and max pulls fade.
/// * **Tremor & drift** — ~9 Hz physiological tremor and a slow wander that
///   scale with force, plus sensor noise and a zero offset that tare removes.
///
/// Deterministic for a given [seed] so it can back tests.
class SimulatedClimber {
  SimulatedClimber({
    this.maxKg = 46,
    double? criticalForceKg,
    this.reactionDelayS = 0.25,
    this.zeroOffsetKg = 1.4,
    this.sensorNoiseKg = 0.03,
    int seed = 42,
  }) : criticalForceKg = criticalForceKg ?? maxKg * 0.36,
       _rng = math.Random(seed) {
    _wPrimeMax = (maxKg - this.criticalForceKg) * 30.0;
    _wPrime = _wPrimeMax;
    _phaseA = _rng.nextDouble() * math.pi * 2;
    _phaseB = _rng.nextDouble() * math.pi * 2;
  }

  /// Fresh max-effort force (kg).
  final double maxKg;

  /// Force sustainable "indefinitely" (kg).
  final double criticalForceKg;

  final double reactionDelayS;

  /// Raw load cell reading with nothing pulling (carabiner + sling).
  final double zeroOffsetKg;
  final double sensorNoiseKg;

  final math.Random _rng;

  late final double _wPrimeMax;
  late double _wPrime;
  late final double _phaseA;
  late final double _phaseB;

  double _t = 0;
  double _force = 0;
  double _tremorNoise = 0;

  // Guidance from the app.
  TestType? _type;
  String _phase = 'IDLE';
  double? _target;
  bool _recording = false;
  double _phaseSince = 0;
  double? _pullStartedAt;

  /// Intent history for the reaction delay: (time, commanded kg, fast?).
  final List<(double, double, bool)> _intent = [(0, 0, false)];

  double get timeS => _t;

  /// True muscle force (kg) without tremor/noise/offset.
  double get force => _force;

  /// Remaining anaerobic capacity 0–1.
  double get wPrimeFraction => _wPrimeMax <= 0 ? 1 : _wPrime / _wPrimeMax;

  /// Highest force currently achievable given fatigue.
  double get capacityKg =>
      criticalForceKg + (maxKg - criticalForceKg) * wPrimeFraction;

  /// Tell the climber what the app is asking for. Call whenever it changes
  /// (cheap to call every UI tick).
  void guide({
    required bool recording,
    TestType? type,
    String phase = '',
    double? targetKg,
  }) {
    final p = phase.toUpperCase();
    if (p != _phase || type != _type || recording != _recording) {
      _phaseSince = _t;
      if (p != 'PULL') _pullStartedAt = null;
    }
    _recording = recording;
    _type = type;
    _phase = p;
    _target = targetKg;
  }

  /// Back to idle (no session).
  void idle() => guide(recording: false);

  /// Advance by [dtS] seconds and return the raw (un-tared) load cell kg.
  double step(double dtS) {
    _t += dtS;
    final (cmd, fast) = _desiredIntent();
    _pushIntent(cmd, fast);
    final (delayedCmd, delayedFast) = _intentAt(_t - reactionDelayS);

    // Fatigue caps what the fingers can deliver.
    final effective = math.min(delayedCmd, capacityKg);

    // First-order lag with rate limits.
    final tau = delayedFast ? 0.045 : 0.14;
    final riseLimit = maxKg * (delayedFast ? 7.5 : 4.5); // kg/s
    final fallLimit = maxKg * 3.5;
    var dF = (effective - _force) / tau * dtS;
    dF = dF.clamp(-fallLimit * dtS, riseLimit * dtS);
    _force = math.max(0, _force + dF);

    _updateWPrime(dtS);

    // Tremor (8–10 Hz), slow postural drift, and sensor noise.
    _tremorNoise = 0.85 * _tremorNoise + 0.15 * _gauss();
    final load = _force;
    final tremor =
        load *
        (0.006 * math.sin(2 * math.pi * 9.2 * _t + _phaseA) +
            0.004 * _tremorNoise);
    // Holding drifts more as W′ runs low (fatigue wobble).
    final wobble =
        load *
        (0.012 + 0.03 * (1 - wPrimeFraction)) *
        (math.sin(2 * math.pi * 0.35 * _t + _phaseB) * 0.6 +
            math.sin(2 * math.pi * 0.9 * _t) * 0.4);
    final sensor = sensorNoiseKg * _gauss();
    return zeroOffsetKg + load + tremor + (load > 0.5 ? wobble : 0) + sensor;
  }

  /// What the climber *wants* to pull right now, and whether it is explosive.
  (double, bool) _desiredIntent() {
    if (!_recording) return (0, false);
    final since = _t - _phaseSince;
    final target = (_target ?? 0) > 0 ? _target! : null;

    switch (_type) {
      case TestType.peakForce:
        if (_phase == 'READY') {
          return since > 1.1 ? (maxKg * 1.08, false) : (0, false);
        }
        if (_phase == 'PULL') {
          _pullStartedAt ??= _t;
          return _t - _pullStartedAt! < 4.2
              ? (maxKg * 1.08, false)
              : (0, false);
        }
        return (0, false);
      case TestType.rfd:
        if (_phase == 'READY') {
          return since > 0.9 ? (maxKg * 0.98, true) : (0, false);
        }
        if (_phase == 'PULL') {
          _pullStartedAt ??= _t;
          return _t - _pullStartedAt! < 1.3 ? (maxKg * 0.98, true) : (0, false);
        }
        return (0, false);
      case TestType.fingerCurl:
        if (target == null) return (0, false);
        return _phase == 'LOWER' ? (target * 0.45, false) : (target, false);
      case TestType.custom:
      case TestType.guidedWorkout:
        // Free log: a relaxed 70 % pull every 9 s.
        final c = since % 9.0;
        return (c > 0.8 && c < 5.3) ? (maxKg * 0.7, false) : (0, false);
      default:
        break;
    }
    if (_phase == 'REST' ||
        _phase == 'PAUSE' ||
        _phase == 'DONE' ||
        _phase == 'IDLE') {
      return (0, false);
    }
    if (target != null) return (target, false);
    if (_phase == 'FREE') {
      final c = since % 9.0;
      return (c > 0.8 && c < 5.3) ? (maxKg * 0.7, false) : (0, false);
    }
    return (0, false);
  }

  void _pushIntent(double cmd, bool fast) {
    final last = _intent.last;
    if ((last.$2 - cmd).abs() > 1e-6 || last.$3 != fast) {
      _intent.add((_t, cmd, fast));
    }
    // Drop entries older than needed for the delay lookup.
    final horizon = _t - reactionDelayS - 1.0;
    while (_intent.length > 2 && _intent[1].$1 < horizon) {
      _intent.removeAt(0);
    }
  }

  (double, bool) _intentAt(double t) {
    var value = _intent.first;
    for (final e in _intent) {
      if (e.$1 <= t) {
        value = e;
      } else {
        break;
      }
    }
    return (value.$2, value.$3);
  }

  void _updateWPrime(double dtS) {
    if (_force > criticalForceKg) {
      _wPrime -= (_force - criticalForceKg) * dtS;
    } else {
      // Recovery is faster the lower the load (full rest ≈ 2× faster).
      final rate = 1.4 * (1 - _force / criticalForceKg).clamp(0.2, 1.0);
      _wPrime += (criticalForceKg - _force) * rate * dtS;
    }
    _wPrime = _wPrime.clamp(0.0, _wPrimeMax);
  }

  double _gauss() {
    // Box–Muller.
    final u1 = math.max(_rng.nextDouble(), 1e-12);
    final u2 = _rng.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
}
