enum TestType {
  peakForce('Peak Force', 'Max effort single pull'),
  rfd('Rate of Force Development', 'Explosive pull, focus on speed to peak'),
  repeaters('Repeaters / CF', '7:3 or custom on/off for endurance & critical force'),
  endurance('Endurance', 'Sustained or long repeaters'),
  custom('Custom / Free', 'Free logging for any protocol'),
  guidedWorkout('Guided Workout', 'Structured training session from library'),
  // Warm-up focused protocols optimized for one-hand wood ring board training before bouldering.
  // Emphasis: progressive activation, control (follow curve), controlled eccentrics, unilateral.
  warmupProgressive('Progressive Warm-up', 'Light→moderate ramp pulls. Start 30%, build to 60-70%. 3-5 smooth reps/hand. Blood flow + recruitment.'),
  followCurve('Follow the Curve', 'Match animated target: ramp 0→70% (4s), HOLD (5s), SLOW RELEASE (3s). Train smooth force + RFD control.'),
  holdRelease('Hold & Controlled Release', 'Isometric hold 6-8s @50-70%, then slow 3-5s eccentric release. Tendon resilience & control.'),
  fingerDrag('Finger Drag', 'One-hand open drag on wood ring: light pressure, slow controlled drag 5-10s. High reps, low load.'),
  fingerCurl('Finger Curls', 'Slow finger curls on ring (3s concentric + 3s eccentric). 8-12 light reps. Prime tendons safely.');

  const TestType(this.label, this.description);

  final String label;
  final String description;

  bool get isWarmup => [
        warmupProgressive,
        followCurve,
        holdRelease,
        fingerDrag,
        fingerCurl,
      ].contains(this);

  /// Suggested starting target as % of estimated max or bodyweight for warm-up (never max effort).
  double get suggestedWarmupPercent => switch (this) {
        warmupProgressive => 0.55,
        followCurve => 0.60,
        holdRelease => 0.55,
        fingerDrag => 0.25,
        fingerCurl => 0.30,
        _ => 0.5,
      };
}
