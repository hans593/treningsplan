// Gjør en økt om til steg for den guidede timeren, med tekst som leses opp.

import 'exercises.dart';
import 'models.dart';

class WorkoutStep {
  final String title;
  final String subtitle;
  final int? seconds; // null = manuelt steg ("Ferdig")
  final String? exerciseId;
  final bool isRest;
  final bool isWork; // arbeid (sett, intervall)
  final bool isPrepare; // «gjør deg klar» før økta starter
  final String speech; // leses opp når steget starter
  final bool countdown; // «tre, to, en» før steget slutter

  const WorkoutStep(
    this.title,
    this.subtitle, {
    this.seconds,
    this.exerciseId,
    this.isRest = false,
    this.isWork = false,
    this.isPrepare = false,
    this.speech = '',
    this.countdown = false,
  });
}

/// Sekunder per sett i Styrke A (kontrollert tempo, ca. 3–4 sek per repetisjon).
int strengthSetSeconds(String id, Session s) {
  final heavy = s.rounds >= 3;
  if (id == 'planke') return heavy ? 45 : 30;
  return heavy ? 50 : 40;
}

/// Gjør tekst lettere å lese opp: «10–12» → «10 til 12», «/» → «per».
String spoken(String t) =>
    t.replaceAllMapped(RegExp(r'(\d+)\s*[–-]\s*(\d+)'), (m) => '${m[1]} til ${m[2]}').replaceAll(' / ', ' per ');

String _tid(int sec) {
  if (sec % 60 == 0) {
    final m = sec ~/ 60;
    return m == 1 ? 'ett minutt' : '$m minutter';
  }
  if (sec > 60) return '${sec ~/ 60} minutter og ${sec % 60} sekunder';
  return '$sec sekunder';
}

String sessionName(Session s) => switch (s.type) {
      SessionType.styrkeA => 'Styrke A, hele kroppen',
      SessionType.styrkeB => 'Styrke B, sirkel ${s.circuit}',
      SessionType.motbakke => 'Motbakkeintervaller, ${s.reps} drag',
      _ => s.title,
    };

List<WorkoutStep> stepsFor(Session s, {bool senior = false}) {
  final steps = <WorkoutStep>[
    WorkoutStep('Gjør deg klar', sessionName(s),
        seconds: 10,
        isPrepare: true,
        speech: '${spoken(sessionName(s))}. Gjør deg klar. Økta starter om ti sekunder.',
        countdown: true),
  ];

  // Legg til en pause med opplesning av neste øvelse.
  void rest(String title, String sub, int sec, String nextName) => steps.add(WorkoutStep(title, sub,
      seconds: sec, isRest: true, countdown: sec >= 15, speech: 'Pause. Hvil i ${_tid(sec)}. Neste: $nextName.'));

  switch (s.type) {
    case SessionType.motbakke:
      steps.add(const WorkoutStep('Oppvarming', 'Rask gange, øk tempoet gradvis',
          seconds: 600, speech: 'Start økt. Oppvarming med rask gange i ti minutter. Øk tempoet gradvis.', countdown: true));
      for (var i = 1; i <= s.reps; i++) {
        steps.add(WorkoutStep('Opp bakken – drag $i av ${s.reps}', 'Rask gange eller lett løping. Anstrengelse 7–8 av 10.',
            seconds: s.workSec,
            isWork: true,
            countdown: true,
            speech: 'Start. Drag $i av ${s.reps}. Opp bakken i ${_tid(s.workSec)}.'));
        if (i < s.reps) {
          steps.add(WorkoutStep('Rolig ned', 'Gå rolig ned bakken og hent deg inn',
              seconds: s.restSec,
              isRest: true,
              countdown: true,
              speech: 'Pause. Gå rolig ned i ${_tid(s.restSec)}.'));
        }
      }
      steps.add(const WorkoutStep('Rask gange', 'Jevnt tempo, du kan fortsatt snakke',
          seconds: 900, speech: 'Bra! Nå rask gange i femten minutter.'));
      steps.add(const WorkoutStep('Nedtrapping', 'Rolig gange',
          seconds: 300, speech: 'Nedtrapping. Rolig gange i fem minutter.', countdown: true));
    case SessionType.styrkeA:
    case SessionType.styrkeB:
      final a = s.type == SessionType.styrkeA;
      steps.add(const WorkoutStep('Oppvarming', 'Marsj på stedet, armsirkler, rolige knebøy',
          seconds: 360,
          countdown: true,
          speech: 'Start økt. Oppvarming i seks minutter. Marsj på stedet, armsirkler og rolige knebøy.'));
      final ids = exercisesFor(s);
      for (var r = 1; r <= s.rounds; r++) {
        for (var k = 0; k < ids.length; k++) {
          final id = ids[k];
          final ex = exercises[id]!;
          final sec = a ? strengthSetSeconds(id, s) : s.workSec;
          final target = a ? repsFor(id, s) : 'Kontrollert tempo, god teknikk';
          final roundTxt = k == 0 ? 'Runde $r av ${s.rounds}. ' : '';
          steps.add(WorkoutStep('${ex.name} – runde $r av ${s.rounds}', target,
              seconds: sec,
              exerciseId: id,
              isWork: true,
              countdown: true,
              speech: '${roundTxt}Start. ${ex.name}. '
                  '${a && id != 'planke' ? '${spoken(target)}.' : '${_tid(sec)}.'}'));
          final lastEx = k == ids.length - 1;
          if (lastEx && r == s.rounds) continue;
          final next = exercises[ids[(k + 1) % ids.length]]!.name;
          if (lastEx) {
            rest('Pause mellom runder', 'Drikk litt og pust rolig', a ? 120 : 90, '$next, runde ${r + 1}');
          } else {
            rest('Pause', a ? 'Rist løs og pust rolig' : 'Gjør klar neste øvelse', a ? 60 : s.restSec, next);
          }
        }
      }
      if (senior) {
        steps.add(const WorkoutStep('Balanse – venstre bein', 'Stå ved en stødig benk',
            seconds: 30, exerciseId: 'balanse', speech: 'Balanse. Stå på venstre bein i tretti sekunder.', countdown: true));
        steps.add(const WorkoutStep('Balanse – høyre bein', 'Stå ved en stødig benk',
            seconds: 30, exerciseId: 'balanse', speech: 'Bytt. Høyre bein i tretti sekunder.', countdown: true));
      }
    case SessionType.langtur:
      steps.add(WorkoutStep('Langtur', 'Rask gange i variert terreng. Du skal kunne snakke.',
          seconds: s.minutes * 60, speech: 'Start økt. Langtur i ${_tid(s.minutes * 60)}. God tur!'));
    case SessionType.kondisjon:
      steps.add(WorkoutStep(s.title, 'Veksle mellom jogging og rask gange. Anstrengelse 4–6.',
          seconds: s.minutes * 60, speech: 'Start økt. ${s.title} i ${_tid(s.minutes * 60)}.'));
    case SessionType.restitusjon:
      steps.add(WorkoutStep(s.title, 'Rolig tempo, løs opp kroppen',
          seconds: s.minutes * 60, speech: 'Start økt. ${s.title} i ${_tid(s.minutes * 60)}.'));
  }
  return steps;
}

const finishSpeech = 'Økta er ferdig. Bra jobba!';
