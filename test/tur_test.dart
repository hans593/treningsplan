import 'package:flutter_test/flutter_test.dart';
import 'package:treningsplan/models.dart';
import 'package:treningsplan/workout_steps.dart';

Session tur(SessionType t, int min, {int reps = 0, int work = 0, int rest = 0}) => Session(
    id: 'x', date: DateTime(2026, 12, 2), type: t, title: 'Tur', minutes: min, effort: Effort.moderat,
    reps: reps, workSec: work, restSec: rest, rounds: 2);

void main() {
  test('langtur 60 min: beskjed etter 15, 30, 45 og 55 min', () {
    final s = tur(SessionType.langtur, 60);
    final ms = milestonesFor(s, stepsFor(s));
    expect(ms.map((m) => m.atSec ~/ 60), [15, 30, 45, 55]);
    expect(ms[0].speech, contains('45 minutter igjen'));
    expect(ms[1].speech, startsWith('Halvveis'));
    expect(ms[3].speech, startsWith('Fem minutter igjen'));
  });

  test('20 min: tre firedeler og 5 min igjen slås sammen', () {
    final s = tur(SessionType.restitusjon, 20);
    final ms = milestonesFor(s, stepsFor(s));
    expect(ms.length, 3);
    expect(ms.last.speech, contains('5 minutter igjen'));
  });

  test('motbakke: prosent regnes av hele økta, ikke ett steg', () {
    final s = tur(SessionType.motbakke, 45, reps: 4, work: 90, rest: 120);
    final steps = stepsFor(s);
    final total = totalSeconds(steps);
    expect(total, 600 + 4 * 90 + 3 * 120 + 900 + 300);
    final ms = milestonesFor(s, steps);
    expect(ms.first.atSec, (total * 0.25).round());
    // Fremdrift midt i siste steg
    expect(progressSeconds(steps, steps.length - 1, 100), total - 100);
    expect(progressSeconds(steps, 0, 5), 0); // gjør-deg-klar teller ikke
  });

  test('styrke får ingen turbeskjeder, turøkter teller ned på slutten', () {
    final st = tur(SessionType.styrkeA, 40);
    expect(milestonesFor(st, stepsFor(st)), isEmpty);
    for (final t in [SessionType.langtur, SessionType.kondisjon, SessionType.restitusjon]) {
      final s = tur(t, 30);
      expect(stepsFor(s).last.countdown, isTrue);
    }
  });
}
