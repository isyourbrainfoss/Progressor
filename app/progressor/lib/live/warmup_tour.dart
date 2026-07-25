import 'package:progressor_core/progressor_core.dart';

/// One step in a multi-phase pre-bouldering warm-up tour.
class WarmupTourStep {
  const WarmupTourStep({
    required this.id,
    required this.title,
    required this.instruction,
    required this.hand,
    this.type,
    this.durationSeconds = 45,
    this.isPause = false,
    this.effortHint = '',
  });

  final String id;
  final String title;
  final String instruction;

  /// Left | Right | Both | — (pause / either).
  final String hand;

  /// Protocol for this step; null for pause / free mobility.
  final TestType? type;

  /// Auto-advance after this many seconds (pause steps wait for Continue).
  final int durationSeconds;

  /// User must tap Continue (mobility, chalk, rest).
  final bool isPause;

  /// Short effort cue shown in UI.
  final String effortHint;
}

/// Default guided tour for one-hand wood-ring / board warm-up before bouldering.
///
/// Order: finger curls each hand → pause → progressive harder → pause →
/// open-hand finger drags each hand → ready.
List<WarmupTourStep> defaultBoulderWarmupTour() {
  return const [
    WarmupTourStep(
      id: 'curl_r',
      title: 'Finger curls',
      hand: 'Right',
      type: TestType.fingerCurl,
      durationSeconds: 40,
      effortHint: 'Light · slow tempo',
      instruction:
          'RIGHT hand: slow finger curls on the ring. 3s up + 3s lower. '
          'Light load only — prime flexor tendons. Breathe.',
    ),
    WarmupTourStep(
      id: 'curl_l',
      title: 'Finger curls',
      hand: 'Left',
      type: TestType.fingerCurl,
      durationSeconds: 40,
      effortHint: 'Light · slow tempo',
      instruction:
          'Switch to LEFT hand. Same slow curls. Match quality, not force. '
          'Note any L/R difference.',
    ),
    WarmupTourStep(
      id: 'pause_mobility',
      title: 'Mobility break',
      hand: '—',
      isPause: true,
      durationSeconds: 0,
      effortHint: 'Optional rest',
      instruction:
          'PAUSE — shake out. Optional: wrist circles, open/close fists, '
          'easy shoulder rolls. Tap Continue when ready for harder warm-up.',
    ),
    WarmupTourStep(
      id: 'prog_r',
      title: 'Progressive pulls',
      hand: 'Right',
      type: TestType.warmupProgressive,
      durationSeconds: 50,
      effortHint: '~30→55% max',
      instruction:
          'RIGHT hand: progressive pulls. Start light (~30%), build toward '
          '~55% over smooth reps. Never to failure. Control the lower.',
    ),
    WarmupTourStep(
      id: 'prog_l',
      title: 'Progressive pulls',
      hand: 'Left',
      type: TestType.warmupProgressive,
      durationSeconds: 50,
      effortHint: '~30→55% max',
      instruction:
          'Switch to LEFT hand. Progressive ramps again. Smooth, no maxing. '
          'Stay well below true peak.',
    ),
    WarmupTourStep(
      id: 'pause_shake',
      title: 'Shake-out',
      hand: '—',
      isPause: true,
      durationSeconds: 0,
      effortHint: 'Brief rest',
      instruction:
          'PAUSE — shake out both hands 20–40s. Chalk if needed. '
          'Next: open-hand finger drags (light). Tap Continue.',
    ),
    WarmupTourStep(
      id: 'drag_r',
      title: 'Four-finger drag',
      hand: 'Right',
      type: TestType.fingerDrag,
      durationSeconds: 45,
      effortHint: 'Very light · open hand',
      instruction:
          'RIGHT hand: open four-finger drag on wood. Very light (~20–30%). '
          'Slow drag across the surface 6–8s. Control > force.',
    ),
    WarmupTourStep(
      id: 'drag_l',
      title: 'Four-finger drag',
      hand: 'Left',
      type: TestType.fingerDrag,
      durationSeconds: 45,
      effortHint: 'Very light · open hand',
      instruction:
          'Switch to LEFT hand. Same open four-finger drag. Light and slow. '
          'Finish when timer ends — then easy boulders.',
    ),
    WarmupTourStep(
      id: 'done',
      title: 'Warm-up complete',
      hand: '—',
      isPause: true,
      durationSeconds: 0,
      effortHint: 'Ready',
      instruction:
          'DONE — tendons primed. Do 3–5 easy boulders building intensity, '
          'then climb. Stop the tour or start Peak/RFD only when fully warm.',
    ),
  ];
}

/// Drives a multi-step warm-up tour with hand switches and pause points.
class WarmupTourController {
  WarmupTourController({List<WarmupTourStep>? steps})
      : steps = steps ?? defaultBoulderWarmupTour();

  final List<WarmupTourStep> steps;

  int _index = 0;
  DateTime? _stepStartedAt;
  bool _active = false;
  bool _finished = false;

  bool get isActive => _active && !_finished;
  bool get isFinished => _finished;
  int get stepIndex => _index;
  int get stepCount => steps.length;
  WarmupTourStep get current => steps[_index.clamp(0, steps.length - 1)];

  /// 1-based step for UI.
  int get stepNumber => _index + 1;

  String get progressLabel => 'Step $stepNumber / $stepCount';

  /// Seconds remaining on timed steps; null on pause / done.
  int? countdownSeconds(DateTime now) {
    if (!_active || _finished) return null;
    final step = current;
    if (step.isPause || step.durationSeconds <= 0) return null;
    final start = _stepStartedAt ?? now;
    final elapsed = now.difference(start).inSeconds;
    final remain = step.durationSeconds - elapsed;
    return remain > 0 ? remain : 0;
  }

  double progressFraction(DateTime now) {
    if (!_active || _finished) return 1;
    final step = current;
    if (step.isPause || step.durationSeconds <= 0) return 0;
    final start = _stepStartedAt ?? now;
    final elapsed = now.difference(start).inMilliseconds;
    return (elapsed / (step.durationSeconds * 1000)).clamp(0.0, 1.0);
  }

  void start(DateTime now) {
    _active = true;
    _finished = false;
    _index = 0;
    _stepStartedAt = now;
  }

  void stop() {
    _active = false;
    _finished = false;
    _index = 0;
    _stepStartedAt = null;
  }

  /// Advance on timer end (timed steps). Returns true if step changed.
  bool tick(DateTime now) {
    if (!_active || _finished) return false;
    final step = current;
    if (step.isPause || step.durationSeconds <= 0) return false;
    final start = _stepStartedAt ?? now;
    if (now.difference(start).inSeconds >= step.durationSeconds) {
      return advance(now);
    }
    return false;
  }

  /// User taps Continue / Next hand / Skip.
  bool advance(DateTime now) {
    if (!_active) return false;
    if (_index >= steps.length - 1) {
      _finished = true;
      _active = false;
      return true;
    }
    _index += 1;
    _stepStartedAt = now;
    if (current.id == 'done') {
      // Stay on done as a pause-like terminal step until stop.
      _finished = false;
    }
    return true;
  }

  bool get needsContinue =>
      isActive && (current.isPause || current.id == 'done');

  /// Protocol for this step, if any.
  TestType? get protocolType => current.type;

  String get hand => current.hand;
}
