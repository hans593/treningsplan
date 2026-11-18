// Gjør en økt om til steg for den guidede timeren.

import 'exercises.dart';
import 'models.dart';

class WorkoutStep {
  final String title;
  final String subtitle;
  final int? seconds; // null = manuelt steg ("Ferdig")
  final String? exerciseId;
  final bool isRest;
  final bool isWork; // hard del (intervall)

  const WorkoutStep(this.title, this.subtitle,
      {this.seconds, this.exerciseId, this.isRest = false, this.isWork = false});
}

List<WorkoutStep> stepsFor(Session s, {bool senior = false}) {
  final steps = <WorkoutStep>[];
  switch (s.type) {
    case SessionType.motbakke:
      steps.add(const WorkoutStep('Oppvarming', 'Rask gange, øk tempoet gradvis', seconds: 600));
      for (var i = 1; i <= s.reps; i++) {
        steps.add(WorkoutStep('Opp bakken – drag $i av ${s.reps}',
            'Rask gange eller lett løping. Anstrengelse 7–8 av 10.',
            seconds: s.workSec, isWork: true));
        if (i < s.reps) {
          steps.add(WorkoutStep('Rolig ned', 'Gå rolig ned bakken og hent deg inn',
              seconds: s.restSec, isRest: true));
        }
      }
      steps.add(const WorkoutStep('Rask gange', 'Jevnt tempo, du kan fortsatt snakke', seconds: 900));
      steps.add(const WorkoutStep('Nedtrapping', 'Rolig gange', seconds: 300));
    case SessionType.styrkeA:
      steps.add(const WorkoutStep('Oppvarming', 'Marsj på stedet, armsirkler, rolige knebøy', seconds: 360));
      final ids = exercisesFor(s);
      for (var r = 1; r <= s.rounds; r++) {
        for (final id in ids) {
          final ex = exercises[id]!;
          steps.add(WorkoutStep('${ex.name} – runde $r av ${s.rounds}', repsFor(id, s), exerciseId: id));
          final last = id == ids.last;
          if (!(last && r == s.rounds)) {
            steps.add(WorkoutStep(last ? 'Pause mellom runder' : 'Pause', 'Rist løs og pust rolig',
                seconds: last ? 120 : 60, isRest: true));
          }
        }
      }
    case SessionType.styrkeB:
      steps.add(const WorkoutStep('Oppvarming', 'Marsj på stedet, armsirkler, rolige knebøy', seconds: 360));
      final ids = exercisesFor(s);
      for (var r = 1; r <= s.rounds; r++) {
        for (final id in ids) {
          final ex = exercises[id]!;
          steps.add(WorkoutStep('${ex.name} – runde $r av ${s.rounds}', 'Kontrollert tempo, god teknikk',
              seconds: s.workSec, exerciseId: id, isWork: true));
          final last = id == ids.last;
          if (!(last && r == s.rounds)) {
            steps.add(WorkoutStep(last ? 'Pause mellom runder' : 'Pause', 'Gjør klar neste øvelse',
                seconds: last ? 90 : s.restSec, isRest: true));
          }
        }
      }
    case SessionType.langtur:
      steps.add(WorkoutStep('Langtur', 'Rask gange i variert terreng. Du skal kunne snakke.',
          seconds: s.minutes * 60));
    case SessionType.kondisjon:
      steps.add(WorkoutStep(s.title, 'Veksle mellom jogging og rask gange. Anstrengelse 4–6.',
          seconds: s.minutes * 60));
    case SessionType.restitusjon:
      steps.add(WorkoutStep(s.title, 'Rolig tempo, løs opp kroppen', seconds: s.minutes * 60));
  }
  if (senior && (s.type == SessionType.styrkeA || s.type == SessionType.styrkeB)) {
    steps.add(const WorkoutStep('Balanse – venstre bein', 'Stå ved en stødig benk', seconds: 30, exerciseId: 'balanse'));
    steps.add(const WorkoutStep('Balanse – høyre bein', 'Stå ved en stødig benk', seconds: 30, exerciseId: 'balanse'));
  }
  return steps;
}
