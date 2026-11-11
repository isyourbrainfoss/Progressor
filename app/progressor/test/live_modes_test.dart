import 'package:flutter_test/flutter_test.dart';
import 'package:progressor/live/live_modes.dart';
import 'package:progressor_core/progressor_core.dart';

void main() {
  test('every mode has a unique, short title and a summary', () {
    final titles = kLiveModes.map((m) => m.title).toList();
    expect(titles.toSet(), hasLength(titles.length));
    for (final m in kLiveModes) {
      expect(m.title.length, lessThanOrEqualTo(18), reason: m.title);
      expect(m.summary, isNotEmpty);
    }
    // Basics first: free, max, repeaters.
    expect(kLiveModes.take(3).map((m) => m.type), [
      TestType.custom,
      TestType.peakForce,
      TestType.repeaters,
    ]);
  });

  test('types without their own mode fall back to free pull', () {
    expect(liveModeFor(TestType.guidedWorkout).type, TestType.custom);
    expect(liveModeFor(TestType.rfd).title, 'Explosive pull');
  });

  test('coach text drops the shouted phase and trailing countdown', () {
    expect(
      plainCoachInstruction('PULL — max effort 3–5s.', 'PULL'),
      'Max effort 3–5s.',
    );
    expect(
      plainCoachInstruction('WORK rep 2/6 — hold ~40% (16.0 kg). 3s', 'WORK'),
      'Rep 2/6 — hold ~40% (16.0 kg).',
    );
    expect(
      plainCoachInstruction('REST 3s — shake, breathe.', 'REST'),
      '3s — shake, breathe.',
    );
    expect(
      plainCoachInstruction('Hold steady and breathe.', 'HOLD'),
      'Hold steady and breathe.',
    );
    expect(plainCoachInstruction('', 'DONE'), '');
  });
}
