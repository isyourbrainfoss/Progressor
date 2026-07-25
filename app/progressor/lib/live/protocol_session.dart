import 'package:progressor_core/progressor_core.dart';

// ---------------------------------------------------------------------------
// Protocol constants (research-backed climbing finger training defaults)
// ---------------------------------------------------------------------------

/// Repeaters: classic 7:3 critical-force style density.
const int kRepeaterWorkSeconds = 7;
const int kRepeaterRestSeconds = 3;
const int kRepeaterReps = 6;

/// ~40% max as hang-load cue for repeaters (submax intermittent).
const double kRepeaterLoadFraction = 0.40;

/// Sustained endurance hold cue (~30–40% max).
const double kEnduranceLoadFraction = 0.35;

/// Follow-the-curve cycle: ramp 5s → hold 5s → slow release 2s (12s total).
const int kFollowCurveCycleMs = 12000;
const int kFollowCurveRampMs = 5000;
const int kFollowCurveHoldMs = 5000;
const int kFollowCurveReleaseMs = 2000;
const double kFollowCurvePeakFraction = 0.55;

/// Match tolerance as fraction of current target (floor/ceil in kg below).
const double kFollowCurveToleranceFraction = 0.12;
const double kFollowCurveToleranceMinKg = 3.0;
const double kFollowCurveToleranceMaxKg = 12.0;

/// Hold & controlled release.
const int kHoldReleaseHoldSeconds = 8;
const int kHoldReleaseReleaseSeconds = 5;
const double kHoldReleaseLoadFraction = 0.55;

/// Warm-up light loads.
const double kFingerDragLoadFraction = 0.25;
const double kFingerCurlLoadFraction = 0.30;
const double kWarmupProgressiveStartFraction = 0.30;
const double kWarmupProgressiveEndFraction = 0.60;
const int kWarmupProgressiveStepSeconds = 4;

/// Peak force pull window guidance.
const int kPeakPullMinSeconds = 3;
const int kPeakPullMaxSeconds = 5;

/// Force thresholds (fraction of userMaxKg) for auto phase detection.
const double kPullDetectFraction = 0.12;
const double kReleaseDetectFraction = 0.08;

/// Soft peak-force target: show prior session peak once known.
const double kSoftPeakLineFraction = 1.0;

// ---------------------------------------------------------------------------
// ProtocolSession
// ---------------------------------------------------------------------------

/// Pure protocol/session engine for Live guided tests.
///
/// Drive with [start] / [stop], feed [onSample] for each force reading, and
/// call [tick] ~every 100ms for timers, target animation, and phase changes.
/// No Flutter UI imports — safe for unit tests and isolate use.
class ProtocolSession {
  ProtocolSession({
    required this.type,
    this.userMaxKg = 40,
    this.hand = 'Right',
    this.repeaterWorkSeconds = kRepeaterWorkSeconds,
    this.repeaterRestSeconds = kRepeaterRestSeconds,
    this.repeaterReps = kRepeaterReps,
  });

  final TestType type;
  final double userMaxKg;
  final String hand;

  /// Configurable repeater density (defaults = 7:3 × 6).
  final int repeaterWorkSeconds;
  final int repeaterRestSeconds;
  final int repeaterReps;

  // ---- public state ----

  bool _active = false;
  DateTime? _startTime;
  DateTime? _phaseStartTime;
  DateTime? _lastTick;

  double? _targetForceKg;
  final List<double> _targetHistoryKg = <double>[];

  String _instruction = '';
  String _phaseLabel = 'IDLE';
  int? _countdownSeconds;
  double? _matchPercent;

  double _sessionPeakKg = 0;
  double _previousPeakKg = 0;
  int _completedReps = 0;

  // Peak / RFD phase tracking
  bool _hasPulled = false;
  int? _timeToPeakMs;
  int? _pullStartMs;
  double _rfdPeakKgPerS = 0;
  double? _lastForceKg;
  int? _lastForceTimeMs;

  // Follow-curve match quality
  double _onTargetSeconds = 0;
  double _matchWindowSeconds = 0;

  // Endurance hold elapsed (seconds while near target)
  double _holdElapsedSeconds = 0;

  // Progressive warmup step index
  int _progressiveStep = 0;

  // ---- getters ----

  bool get isActive => _active;

  double? get targetForceKg => _targetForceKg;

  /// Target path sampled on each [tick] (parallel timeline for charting).
  List<double> get targetHistoryKg => List<double>.unmodifiable(_targetHistoryKg);

  String get instruction => _instruction;

  String get phaseLabel => _phaseLabel;

  int? get countdownSeconds => _countdownSeconds;

  double? get matchPercent => _matchPercent;

  /// Extra fields merged into [PullTest.metrics] on save.
  Map<String, dynamic> get metricsExtras {
    final m = <String, dynamic>{
      'protocol': type.name,
      'hand': hand,
      'userMaxKg': userMaxKg,
      'sessionPeakKg': _sessionPeakKg > 0 ? _sessionPeakKg : null,
      'completedReps': _completedReps > 0 ? _completedReps : null,
    };

    switch (type) {
      case TestType.rfd:
        m['timeToPeakMs'] = _timeToPeakMs;
        m['rfdPeakKgPerS'] =
            _rfdPeakKgPerS > 0 ? double.parse(_rfdPeakKgPerS.toStringAsFixed(2)) : null;
        m['emphasis'] = 'time_to_peak';
      case TestType.peakForce:
        m['pullWindowHintS'] = '$kPeakPullMinSeconds–$kPeakPullMaxSeconds';
      case TestType.repeaters:
        m['workSeconds'] = repeaterWorkSeconds;
        m['restSeconds'] = repeaterRestSeconds;
        m['plannedReps'] = repeaterReps;
        m['targetLoadFraction'] = kRepeaterLoadFraction;
        m['targetForceKg'] = _staticTarget(kRepeaterLoadFraction);
      case TestType.endurance:
        m['targetLoadFraction'] = kEnduranceLoadFraction;
        m['targetForceKg'] = _staticTarget(kEnduranceLoadFraction);
        m['holdElapsedSeconds'] = double.parse(_holdElapsedSeconds.toStringAsFixed(1));
      case TestType.followCurve:
        m['warmupMatchPercent'] = _matchPercent?.round();
        m['targetPeakKg'] = _staticTarget(kFollowCurvePeakFraction);
        m['cycleMs'] = kFollowCurveCycleMs;
      case TestType.holdRelease:
        m['holdSeconds'] = kHoldReleaseHoldSeconds;
        m['releaseSeconds'] = kHoldReleaseReleaseSeconds;
        m['targetForceKg'] = _staticTarget(kHoldReleaseLoadFraction);
      case TestType.fingerDrag:
        m['targetLoadFraction'] = kFingerDragLoadFraction;
        m['targetForceKg'] = _staticTarget(kFingerDragLoadFraction);
      case TestType.fingerCurl:
        m['targetLoadFraction'] = kFingerCurlLoadFraction;
        m['targetForceKg'] = _staticTarget(kFingerCurlLoadFraction);
      case TestType.warmupProgressive:
        m['startFraction'] = kWarmupProgressiveStartFraction;
        m['endFraction'] = kWarmupProgressiveEndFraction;
      case TestType.warmupTour:
        m['mode'] = 'warmup_tour';
      case TestType.custom:
      case TestType.guidedWorkout:
        m['mode'] = 'free_log';
    }

    m.removeWhere((_, v) => v == null);
    return m;
  }

  // ---- lifecycle ----

  void start(DateTime now) {
    _active = true;
    _startTime = now;
    _phaseStartTime = now;
    _lastTick = now;
    _targetHistoryKg.clear();
    _targetForceKg = null;
    _countdownSeconds = null;
    _matchPercent = null;
    _sessionPeakKg = 0;
    _previousPeakKg = 0;
    _completedReps = 0;
    _hasPulled = false;
    _timeToPeakMs = null;
    _pullStartMs = null;
    _rfdPeakKgPerS = 0;
    _lastForceKg = null;
    _lastForceTimeMs = null;
    _onTargetSeconds = 0;
    _matchWindowSeconds = 0;
    _holdElapsedSeconds = 0;
    _progressiveStep = 0;
    _enterInitialPhase(now);
  }

  void stop() {
    if (!_active) return;
    _active = false;
    if (_phaseLabel != 'DONE') {
      _phaseLabel = 'DONE';
    }
    _countdownSeconds = null;
    // Keep last instruction as summary-friendly text.
    if (_instruction.isEmpty || _instruction.startsWith('Session')) {
      _instruction = 'Session stopped.';
    }
  }

  /// Called on each force sample while the session is active.
  void onSample(ForceSample s) {
    if (!_active) return;

    // Detect pull onset before peak bookkeeping so TTP is correct on first spike.
    final detect = userMaxKg * kPullDetectFraction;
    if (!_hasPulled && s.forceKg >= detect) {
      _hasPulled = true;
      _pullStartMs ??= s.timeMs;
    }

    if (s.forceKg > _sessionPeakKg) {
      if (_sessionPeakKg > 0) {
        _previousPeakKg = _sessionPeakKg;
      }
      _sessionPeakKg = s.forceKg;
      // Time-to-peak from pull onset (relative sample clock).
      if (_hasPulled || _phaseLabel == 'PULL') {
        _timeToPeakMs = s.timeMs - (_pullStartMs ?? s.timeMs);
      }
    }

    // Instantaneous RFD estimate between consecutive samples.
    if (_lastForceKg != null && _lastForceTimeMs != null) {
      final dtS = (s.timeMs - _lastForceTimeMs!) / 1000.0;
      if (dtS > 0) {
        final rfd = (s.forceKg - _lastForceKg!) / dtS;
        if (rfd > _rfdPeakKgPerS) _rfdPeakKgPerS = rfd;
      }
    }
    _lastForceKg = s.forceKg;
    _lastForceTimeMs = s.timeMs;

    _updateForceDrivenPhases(s);
  }

  /// Called every tick (~100ms) for timers / target animation.
  void tick(DateTime now) {
    if (!_active || _startTime == null) return;
    final prev = _lastTick ?? _startTime!;
    final dtS = now.difference(prev).inMicroseconds / 1e6;
    _lastTick = now;

    switch (type) {
      case TestType.peakForce:
        _tickPeakForce(now);
      case TestType.rfd:
        _tickRfd(now);
      case TestType.repeaters:
        _tickRepeaters(now);
      case TestType.endurance:
        _tickEndurance(dtS);
      case TestType.custom:
      case TestType.guidedWorkout:
        _tickFree();
      case TestType.followCurve:
        _tickFollowCurve(now, dtS);
      case TestType.holdRelease:
        _tickHoldRelease(now);
      case TestType.warmupProgressive:
        _tickWarmupProgressive(now);
      case TestType.fingerDrag:
        _tickFingerDrag(now);
      case TestType.fingerCurl:
        _tickFingerCurl(now);
      case TestType.warmupTour:
        // Tour is orchestrated by WarmupTourController; individual steps use their own types.
        _tickFree();
    }

    // Record target history for chart path (null → 0 for continuous series).
    _targetHistoryKg.add(_targetForceKg ?? 0);
  }

  // ---- init per type ----

  void _enterInitialPhase(DateTime now) {
    switch (type) {
      case TestType.peakForce:
        _setPhase('READY', now);
        _targetForceKg = null;
        _instruction =
            'Max single pull ${kPeakPullMinSeconds}–${kPeakPullMaxSeconds}s. Rest fully between reps. Get set…';
      case TestType.rfd:
        _setPhase('READY', now);
        _targetForceKg = null;
        _instruction =
            'Explosive pull — as fast as possible to ~80–100% max. Emphasize speed to peak, not long grind.';
      case TestType.repeaters:
        _setPhase('WORK', now);
        _completedReps = 0;
        _targetForceKg = _staticTarget(kRepeaterLoadFraction);
        _countdownSeconds = repeaterWorkSeconds;
        _instruction =
            'Repeaters: ${repeaterWorkSeconds}s on / ${repeaterRestSeconds}s off × $repeaterReps. '
            'Hold ~${(kRepeaterLoadFraction * 100).round()}% max '
            '(${_targetForceKg!.toStringAsFixed(1)} kg).';
      case TestType.endurance:
        _setPhase('HOLD', now);
        _targetForceKg = _staticTarget(kEnduranceLoadFraction);
        _countdownSeconds = null;
        _instruction =
            'Hold steady ~${(kEnduranceLoadFraction * 100).round()}% max '
            '(${_targetForceKg!.toStringAsFixed(1)} kg) until form breaks. Smooth tension, breathe.';
      case TestType.custom:
      case TestType.guidedWorkout:
        _setPhase('FREE', now);
        _targetForceKg = null;
        _instruction = 'Free log — pull as desired';
      case TestType.followCurve:
        _setPhase('RAMP', now);
        _targetForceKg = 0;
        _instruction =
            'FOLLOW THE CURVE: match the target line — ramp, hold, slow release. Stay within ~12%.';
      case TestType.holdRelease:
        _setPhase('HOLD', now);
        _targetForceKg = _staticTarget(kHoldReleaseLoadFraction);
        _countdownSeconds = kHoldReleaseHoldSeconds;
        _instruction =
            'HOLD ${_countdownSeconds}s at ~${(kHoldReleaseLoadFraction * 100).round()}% max '
            '(${_targetForceKg!.toStringAsFixed(1)} kg). Then slow controlled release.';
      case TestType.warmupProgressive:
        _setPhase('RAMP', now);
        _progressiveStep = 0;
        _applyProgressiveStep();
      case TestType.fingerDrag:
        _setPhase('WORK', now);
        _targetForceKg = _staticTarget(kFingerDragLoadFraction);
        _instruction =
            'FINGER DRAG: light ~${(kFingerDragLoadFraction * 100).round()}% '
            '(${_targetForceKg!.toStringAsFixed(1)} kg). Slow controlled drag across the ring.';
      case TestType.fingerCurl:
        _setPhase('CURL', now);
        _targetForceKg = _staticTarget(kFingerCurlLoadFraction);
        _instruction =
            'FINGER CURLS: slow tempo ~${(kFingerCurlLoadFraction * 100).round()}% '
            '(${_targetForceKg!.toStringAsFixed(1)} kg). 3s curl up + 3s lower.';
      case TestType.warmupTour:
        _setPhase('FREE', now);
        _targetForceKg = null;
        _instruction = 'Use Warm-up Tour from Live for the guided multi-step session.';
    }
  }

  // ---- per-protocol ticks ----

  void _tickPeakForce(DateTime now) {
    final elapsed = _phaseElapsed(now);
    // Soft target at previous peak once we have one.
    if (_previousPeakKg > 0 || _sessionPeakKg > 0) {
      final soft = _previousPeakKg > 0 ? _previousPeakKg : _sessionPeakKg;
      if (_hasPulled && soft > 0) {
        _targetForceKg = soft * kSoftPeakLineFraction;
      }
    }

    switch (_phaseLabel) {
      case 'READY':
        final cd = 3 - elapsed.inSeconds;
        _countdownSeconds = cd > 0 ? cd : null;
        if (elapsed.inSeconds >= 3 || _hasPulled) {
          _setPhase('PULL', now);
          _pullStartMs ??= _relativeMs(now);
          _instruction =
              'PULL — max effort ${kPeakPullMinSeconds}–${kPeakPullMaxSeconds}s. Full recruitment, then rest.';
          _countdownSeconds = kPeakPullMaxSeconds;
        } else {
          _instruction = 'READY — max single pull coming. Rest fully between reps.';
        }
      case 'PULL':
        final remain = kPeakPullMaxSeconds - elapsed.inSeconds;
        _countdownSeconds = remain > 0 ? remain : 0;
        if (elapsed.inSeconds >= kPeakPullMaxSeconds) {
          _setPhase('DONE', now);
          _countdownSeconds = null;
          _instruction =
              'DONE — peak ${_sessionPeakKg.toStringAsFixed(1)} kg. Rest fully before another rep.';
          _targetForceKg = _sessionPeakKg > 0 ? _sessionPeakKg : _targetForceKg;
        } else if (elapsed.inSeconds >= kPeakPullMinSeconds) {
          _instruction =
              'PULL — hold max if fresh (${remain}s). Release when form fades.';
        }
      case 'DONE':
        _countdownSeconds = null;
      default:
        break;
    }
  }

  void _tickRfd(DateTime now) {
    final elapsed = _phaseElapsed(now);
    switch (_phaseLabel) {
      case 'READY':
        final cd = 2 - elapsed.inSeconds;
        _countdownSeconds = cd > 0 ? cd : null;
        if (elapsed.inSeconds >= 2 || _hasPulled) {
          _setPhase('PULL', now);
          _pullStartMs ??= _relativeMs(now);
          _countdownSeconds = null;
          _instruction =
              'EXPLODE — fire to ~80–100% max as fast as possible. Snap, do not grind.';
        } else {
          _instruction = 'READY — explosive RFD pull. Arm the tendons, then fire.';
        }
      case 'PULL':
        if (_timeToPeakMs != null && elapsed.inMilliseconds > 800) {
          // After a peak and brief window, finish if force dropped.
          final f = _lastForceKg ?? 0;
          if (_sessionPeakKg > 0 && f < _sessionPeakKg * 0.4 && elapsed.inSeconds >= 1) {
            _setPhase('DONE', now);
            final ttp = _timeToPeakMs;
            _instruction = ttp != null
                ? 'DONE — time to peak ${ttp} ms. Rest, then another snap if fresh.'
                : 'DONE — rest fully, then another explosive rep if desired.';
          }
        }
        if (elapsed.inSeconds >= 6) {
          _setPhase('DONE', now);
          final ttp = _timeToPeakMs;
          _instruction = ttp != null
              ? 'DONE — time to peak ${ttp} ms · peak ${_sessionPeakKg.toStringAsFixed(1)} kg.'
              : 'DONE — session peak ${_sessionPeakKg.toStringAsFixed(1)} kg.';
        }
      case 'DONE':
        _countdownSeconds = null;
      default:
        break;
    }
  }

  void _tickRepeaters(DateTime now) {
    final elapsed = _phaseElapsed(now);
    _targetForceKg = _staticTarget(kRepeaterLoadFraction);

    if (_phaseLabel == 'WORK') {
      final remain = repeaterWorkSeconds - elapsed.inSeconds;
      _countdownSeconds = remain > 0 ? remain : 0;
      _instruction =
          'WORK rep ${_completedReps + 1}/$repeaterReps — hold '
          '~${(kRepeaterLoadFraction * 100).round()}% '
          '(${_targetForceKg!.toStringAsFixed(1)} kg). ${_countdownSeconds}s';
      if (elapsed.inSeconds >= repeaterWorkSeconds) {
        _completedReps += 1;
        if (_completedReps >= repeaterReps) {
          _setPhase('DONE', now);
          _countdownSeconds = null;
          _targetForceKg = null;
          _instruction =
              'DONE — $repeaterReps reps complete. Shake out. Note CF-style sustainability.';
        } else {
          _setPhase('REST', now);
          _countdownSeconds = repeaterRestSeconds;
          _instruction =
              'REST — fully unload ${_countdownSeconds}s. Next rep ${_completedReps + 1}/$repeaterReps.';
        }
      }
    } else if (_phaseLabel == 'REST') {
      final remain = repeaterRestSeconds - elapsed.inSeconds;
      _countdownSeconds = remain > 0 ? remain : 0;
      _targetForceKg = 0;
      _instruction =
          'REST ${_countdownSeconds}s — shake, breathe. Next: rep ${_completedReps + 1}/$repeaterReps.';
      if (elapsed.inSeconds >= repeaterRestSeconds) {
        _setPhase('WORK', now);
        _countdownSeconds = repeaterWorkSeconds;
        _targetForceKg = _staticTarget(kRepeaterLoadFraction);
        _instruction =
            'WORK rep ${_completedReps + 1}/$repeaterReps — re-engage to target.';
      }
    } else if (_phaseLabel == 'DONE') {
      _countdownSeconds = null;
      _targetForceKg = null;
    }
  }

  void _tickEndurance(double dtS) {
    _targetForceKg = _staticTarget(kEnduranceLoadFraction);
    final f = _lastForceKg;
    if (f != null && _targetForceKg != null) {
      final tol = (_targetForceKg! * 0.20).clamp(2.0, 15.0);
      if ((f - _targetForceKg!).abs() <= tol && f > 1.0) {
        _holdElapsedSeconds += dtS.clamp(0.0, 0.5);
      }
    }
    final holdS = _holdElapsedSeconds.floor();
    _countdownSeconds = null;
    _phaseLabel = 'HOLD';
    _instruction =
        'HOLD steady ~${(kEnduranceLoadFraction * 100).round()}% '
        '(${_targetForceKg!.toStringAsFixed(1)} kg). '
        'Elapsed near target: ${holdS}s. Stop when form breaks.';
  }

  void _tickFree() {
    _targetForceKg = null;
    _countdownSeconds = null;
    _phaseLabel = 'FREE';
    _instruction = 'Free log — pull as desired';
  }

  void _tickFollowCurve(DateTime now, double dtS) {
    final elapsedMs =
        now.difference(_startTime!).inMilliseconds % kFollowCurveCycleMs;
    final peak = _staticTarget(kFollowCurvePeakFraction);
    double target;
    String phase;

    if (elapsedMs < kFollowCurveRampMs) {
      target = (elapsedMs / kFollowCurveRampMs) * peak;
      phase = 'RAMP';
      _instruction = 'RAMP UP smoothly — match the rising target line.';
    } else if (elapsedMs < kFollowCurveRampMs + kFollowCurveHoldMs) {
      target = peak;
      phase = 'HOLD';
      _instruction = 'HOLD steady on the target — smooth tension, no bounce.';
    } else {
      final relMs = elapsedMs - kFollowCurveRampMs - kFollowCurveHoldMs;
      final relT = (relMs / kFollowCurveReleaseMs).clamp(0.0, 1.0);
      target = peak * (1.0 - relT);
      phase = 'RELEASE';
      _instruction = 'SLOW RELEASE — lower with control to zero.';
    }

    _phaseLabel = phase;
    _targetForceKg = target;
    _countdownSeconds = null;

    // Match quality advances on each tick while we have a live force reading.
    if (_lastForceKg != null) {
      _accumulateMatch(_lastForceKg!, target, dtS);
    }
  }

  void _tickHoldRelease(DateTime now) {
    final elapsed = _phaseElapsed(now);
    final holdTarget = _staticTarget(kHoldReleaseLoadFraction);

    if (_phaseLabel == 'HOLD') {
      _targetForceKg = holdTarget;
      final remain = kHoldReleaseHoldSeconds - elapsed.inSeconds;
      _countdownSeconds = remain > 0 ? remain : 0;
      _instruction =
          'HOLD ${_countdownSeconds}s @ ~${(kHoldReleaseLoadFraction * 100).round()}% '
          '(${holdTarget.toStringAsFixed(1)} kg). Focus tension.';
      if (elapsed.inSeconds >= kHoldReleaseHoldSeconds) {
        _setPhase('RELEASE', now);
        _countdownSeconds = kHoldReleaseReleaseSeconds;
        _targetForceKg = holdTarget; // soft cue while lowering
        _instruction =
            'RELEASE — slow controlled eccentric ${_countdownSeconds}s. Tendon gold!';
      }
    } else if (_phaseLabel == 'RELEASE') {
      final remain = kHoldReleaseReleaseSeconds - elapsed.inSeconds;
      _countdownSeconds = remain > 0 ? remain : 0;
      // Animate target down over release window.
      final t = (elapsed.inMilliseconds / (kHoldReleaseReleaseSeconds * 1000))
          .clamp(0.0, 1.0);
      _targetForceKg = holdTarget * (1.0 - t);
      _instruction =
          'RELEASE — control the lowering (${_countdownSeconds}s). Do not dump tension.';
      if (elapsed.inSeconds >= kHoldReleaseReleaseSeconds) {
        _setPhase('DONE', now);
        _countdownSeconds = null;
        _targetForceKg = 0;
        _instruction = 'DONE — shake out. Repeat on the other hand if warm-up set continues.';
      }
    } else if (_phaseLabel == 'DONE') {
      _countdownSeconds = null;
    }
  }

  void _tickWarmupProgressive(DateTime now) {
    final totalSteps = _progressiveStepCount();
    final elapsed = now.difference(_startTime!).inSeconds;
    final step = (elapsed ~/ kWarmupProgressiveStepSeconds).clamp(0, totalSteps - 1);
    if (step != _progressiveStep) {
      _progressiveStep = step;
      _applyProgressiveStep();
    } else {
      // Keep countdown to next step.
      final into = elapsed % kWarmupProgressiveStepSeconds;
      final remain = kWarmupProgressiveStepSeconds - into;
      _countdownSeconds = _progressiveStep < totalSteps - 1 ? remain : null;
    }
    _phaseLabel = 'RAMP';
  }

  void _tickFingerDrag(DateTime now) {
    _targetForceKg = _staticTarget(kFingerDragLoadFraction);
    _phaseLabel = 'WORK';
    final elapsed = now.difference(_startTime!).inSeconds;
    // Gentle coaching every ~6s.
    if ((elapsed ~/ 6).isEven) {
      _instruction =
          'FINGER DRAG: light ~${(kFingerDragLoadFraction * 100).round()}% '
          '(${_targetForceKg!.toStringAsFixed(1)} kg). Slow drag, breathe, control > force.';
    } else {
      _instruction =
          'Keep light + slow. Switch hand soon if one-hand warm-up. Quality over load.';
    }
    _countdownSeconds = null;
  }

  void _tickFingerCurl(DateTime now) {
    _targetForceKg = _staticTarget(kFingerCurlLoadFraction);
    final elapsed = now.difference(_startTime!).inSeconds;
    // 3s concentric + 3s eccentric tempo.
    final phaseSec = elapsed % 6;
    final concentric = phaseSec < 3;
    final remain = concentric ? (3 - phaseSec) : (6 - phaseSec);
    _countdownSeconds = remain;
    if (concentric) {
      _phaseLabel = 'CURL';
      _instruction =
          'CURL UP (${_countdownSeconds}s) — slow concentric ~'
          '${(kFingerCurlLoadFraction * 100).round()}% '
          '(${_targetForceKg!.toStringAsFixed(1)} kg).';
    } else {
      _phaseLabel = 'LOWER';
      _instruction =
          'LOWER (${_countdownSeconds}s) — slow eccentric. Feel flexors warm. Quality reps.';
    }
  }

  // ---- force-driven phase helpers ----

  void _updateForceDrivenPhases(ForceSample s) {
    if (type != TestType.peakForce && type != TestType.rfd) return;

    final detect = userMaxKg * kPullDetectFraction;
    final releaseThr = userMaxKg * kReleaseDetectFraction;

    // onSample may already have marked pull onset; still advance READY → PULL.
    if (_hasPulled && _phaseLabel == 'READY') {
      _setPhase('PULL', _lastTick ?? DateTime.now());
      if (type == TestType.peakForce) {
        _instruction =
            'PULL — max effort ${kPeakPullMinSeconds}–${kPeakPullMaxSeconds}s.';
        _countdownSeconds = kPeakPullMaxSeconds;
      } else {
        _instruction = 'EXPLODE — fire to peak as fast as possible.';
      }
    }

    // Release after a meaningful peak → DONE for peak (optional early finish).
    if (type == TestType.peakForce &&
        _phaseLabel == 'PULL' &&
        _sessionPeakKg > detect * 1.5 &&
        s.forceKg < releaseThr &&
        s.timeMs - (_pullStartMs ?? 0) >= kPeakPullMinSeconds * 1000) {
      _setPhase('DONE', _lastTick ?? DateTime.now());
      _countdownSeconds = null;
      _instruction =
          'DONE — peak ${_sessionPeakKg.toStringAsFixed(1)} kg. Rest fully before another rep.';
      _targetForceKg = _sessionPeakKg;
    }
    if (type == TestType.rfd &&
        _phaseLabel == 'PULL' &&
        _sessionPeakKg > detect &&
        s.forceKg < _sessionPeakKg * 0.35 &&
        (_timeToPeakMs != null || s.timeMs - (_pullStartMs ?? 0) > 300)) {
      if (_timeToPeakMs == null && _pullStartMs != null) {
        _timeToPeakMs = s.timeMs - _pullStartMs!;
      }
      _setPhase('DONE', _lastTick ?? DateTime.now());
      final ttp = _timeToPeakMs;
      _instruction = ttp != null
          ? 'DONE — time to peak $ttp ms · peak ${_sessionPeakKg.toStringAsFixed(1)} kg.'
          : 'DONE — peak ${_sessionPeakKg.toStringAsFixed(1)} kg.';
    }
  }

  void _accumulateMatch(double forceKg, double target, double dtS) {
    if (dtS <= 0) return;
    final capped = dtS.clamp(0.0, 0.25);
    _matchWindowSeconds += capped;
    final tol = (target * kFollowCurveToleranceFraction)
        .clamp(kFollowCurveToleranceMinKg, kFollowCurveToleranceMaxKg);
    if ((forceKg - target).abs() <= tol) {
      _onTargetSeconds += capped;
    }
    if (_matchWindowSeconds > 0) {
      _matchPercent =
          ((_onTargetSeconds / _matchWindowSeconds) * 100).clamp(0.0, 100.0);
    }
  }

  // ---- progressive warm-up helpers ----

  int _progressiveStepCount() {
    // 30% → 60% in ~10% steps: 30, 40, 50, 60 → 4 steps.
    const start = kWarmupProgressiveStartFraction;
    const end = kWarmupProgressiveEndFraction;
    const step = 0.10;
    return (((end - start) / step).round()) + 1;
  }

  void _applyProgressiveStep() {
    const start = kWarmupProgressiveStartFraction;
    const step = 0.10;
    final frac =
        (start + _progressiveStep * step).clamp(start, kWarmupProgressiveEndFraction);
    _targetForceKg = _staticTarget(frac);
    _phaseLabel = 'RAMP';
    _countdownSeconds = kWarmupProgressiveStepSeconds;
    _instruction =
        'Progressive warm-up: suggested ~${(frac * 100).round()}% max '
        '(${_targetForceKg!.toStringAsFixed(1)} kg). Smooth ramps, never to failure. Breathe.';
  }

  // ---- utilities ----

  double _staticTarget(double fraction) => userMaxKg * fraction;

  void _setPhase(String label, DateTime now) {
    _phaseLabel = label;
    _phaseStartTime = now;
  }

  Duration _phaseElapsed(DateTime now) {
    final start = _phaseStartTime ?? _startTime ?? now;
    return now.difference(start);
  }

  int _relativeMs(DateTime now) {
    final start = _startTime ?? now;
    return now.difference(start).inMilliseconds;
  }
}
