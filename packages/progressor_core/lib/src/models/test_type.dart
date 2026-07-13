enum TestType {
  peakForce('Peak Force', 'Max effort single pull'),
  rfd('Rate of Force Development', 'Explosive pull, focus on speed to peak'),
  repeaters('Repeaters / CF', '7:3 or custom on/off for endurance & critical force'),
  endurance('Endurance', 'Sustained or long repeaters'),
  custom('Custom / Free', 'Free logging for any protocol'),
  guidedWorkout('Guided Workout', 'Structured training session from library');

  const TestType(this.label, this.description);

  final String label;
  final String description;
}
