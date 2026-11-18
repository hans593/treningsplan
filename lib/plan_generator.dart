// Lager treningsplanen fra profilen.
//
// Hovedregler:
// * Fire faser: tilvenning, oppbygging, kapasitet, vedlikehold. Siste uke er testuke.
// * Hver 4. uke er lettuke (ca. 20–30 % mindre).
// * Ukentlig belastning øker maks 10 % fra forrige vanlige uke.
// * Harde økter (intervaller) legges aldri to dager på rad.

import 'dart:math';

import 'models.dart';

/// Intervallstige: (antall drag, sekunder per drag).
const hillLadder = <(int, int)>[
  (4, 60), (5, 60), (6, 60), (5, 90), (6, 90), (4, 120),
  (5, 120), (6, 120), (4, 180), (5, 180), (4, 240), (5, 240),
];

/// Ukemaler: ukedag (0 = mandag) -> økttype.
Map<int, SessionType> weekTemplate(int daysPerWeek) {
  switch (daysPerWeek.clamp(3, 6)) {
    case 3:
      return {0: SessionType.motbakke, 2: SessionType.styrkeA, 5: SessionType.langtur};
    case 4:
      return {
        0: SessionType.motbakke,
        1: SessionType.styrkeA,
        3: SessionType.styrkeB,
        5: SessionType.langtur,
      };
    case 5:
      return {
        0: SessionType.motbakke,
        1: SessionType.styrkeA,
        2: SessionType.langtur,
        3: SessionType.styrkeB,
        5: SessionType.kondisjon,
      };
    default:
      return {
        0: SessionType.motbakke,
        1: SessionType.styrkeA,
        2: SessionType.langtur,
        3: SessionType.styrkeB,
        4: SessionType.restitusjon,
        5: SessionType.kondisjon,
      };
  }
}

DateTime mondayOf(DateTime d) => dateOnly(d).subtract(Duration(days: d.weekday - 1));

bool isDeloadWeek(int index, int totalWeeks) =>
    index == totalWeeks - 1 || (index > 0 && (index + 1) % 4 == 0);

String phaseFor(int index, int totalWeeks) {
  if (index == totalWeeks - 1 && totalWeeks > 1) return 'Testuke';
  final f = index / totalWeeks;
  if (f < 0.18) return 'Tilvenning';
  if (f < 0.55) return 'Oppbygging';
  if (f < 0.86) return 'Kapasitet';
  return 'Vedlikehold';
}

int fitnessOffset(Fitness f) => switch (f) {
      Fitness.liteAktiv => -1,
      Fitness.gaarRaskt => 0,
      Fitness.kanJogge => 1,
      Fitness.trenerJevnlig => 2,
    };

/// Antall progresjonssteg som skal brukes for å nå toppnivå.
int progressionSpan(int totalWeeks) {
  var count = 0;
  final peakWeek = (totalWeeks * 0.86).floor();
  for (var i = 0; i < peakWeek; i++) {
    if (!isDeloadWeek(i, totalWeeks)) count++;
  }
  return max(1, count - 1);
}

/// Nivå 0–1 for en uke ut fra progresjonssteg og form.
double levelFor(Profile p, int progression) {
  final span = progressionSpan(p.totalWeeks);
  return ((progression + fitnessOffset(p.fitness)) / span).clamp(0.0, 1.0);
}

int _round5(num v) => (v / 5).round() * 5;

List<Session> sessionsForWeek(Profile p, WeekPlan w) {
  final lvl = levelFor(p, w.progression);
  final deload = w.deload;
  final template = weekTemplate(p.daysPerWeek);
  final sessions = <Session>[];

  template.forEach((weekday, type) {
    final date = w.monday.add(Duration(days: weekday));
    if (date.isBefore(p.startDate) || date.isAfter(p.endDate)) return;
    sessions.add(_buildSession(p, w, type, date, lvl, deload));
  });
  return sessions;
}

Session _buildSession(Profile p, WeekPlan w, SessionType type, DateTime date, double lvl, bool deload) {
  final id = 'u${w.index}-${date.weekday}-${type.name}';
  final hasHills = p.activities.contains(Activity.motbakker);
  final jogs = p.activities.contains(Activity.jogging);

  switch (type) {
    case SessionType.motbakke:
      final maxIdx = switch (p.intensity) {
        Intensity.rolig => 5,
        Intensity.moderat => 10,
        Intensity.krevende => 11,
      };
      var idx = (lvl * maxIdx).round();
      if (deload) idx = max(0, idx - 3);
      var (reps, work) = hillLadder[idx];
      if (p.intensity == Intensity.krevende && !deload && lvl > 0.3) reps += 1;
      if (deload) reps = max(3, reps - 1);
      final rest = work <= 90 ? 120 : 180;
      final minutes = _round5(10 + reps * (work + rest) / 60 + 20);
      return Session(
        id: id,
        date: date,
        type: type,
        title: hasHills ? 'Motbakkeintervaller' : 'Intervaller, rask gange',
        minutes: minutes,
        effort: Effort.hard,
        reps: reps,
        workSec: work,
        restSec: rest,
      );
    case SessionType.styrkeA:
    case SessionType.styrkeB:
      var rounds = lvl < 0.25 ? 2 : 3;
      if (p.intensity == Intensity.krevende && lvl > 0.75) rounds = 4;
      if (p.intensity == Intensity.rolig) rounds = min(rounds, 3);
      if (deload) rounds = 2;
      if (type == SessionType.styrkeA) {
        return Session(
          id: id,
          date: date,
          type: type,
          title: 'Styrke A – manualer',
          minutes: 10 + rounds * 10,
          effort: Effort.moderat,
          rounds: rounds,
          circuit: 0,
        );
      }
      final circuit = (w.index % 3) + 1;
      final easyStart = w.index < 3 || (p.fitness == Fitness.liteAktiv && w.index < 6);
      final work = easyStart ? 30 : 40;
      final rest = 60 - work;
      return Session(
        id: id,
        date: date,
        type: type,
        title: 'Styrke B – sirkel $circuit',
        minutes: _round5(10 + rounds * 5 + (rounds - 1) * 1.5),
        effort: Effort.moderat,
        rounds: rounds,
        circuit: circuit,
        workSec: work,
        restSec: rest,
      );
    case SessionType.langtur:
      final base = p.minutesPerSession + 15;
      var top = min(90, p.minutesPerSession + 45);
      if (p.intensity == Intensity.rolig) top -= 10;
      var minutes = _round5(base + lvl * max(0, top - base));
      if (deload) minutes = _round5(minutes * 0.8);
      return Session(
        id: id,
        date: date,
        type: type,
        title: 'Langtur – rask gange',
        minutes: minutes,
        effort: Effort.lett,
      );
    case SessionType.kondisjon:
      var minutes = _round5(25 + lvl * 30);
      if (deload) minutes = _round5(minutes * 0.8);
      return Session(
        id: id,
        date: date,
        type: type,
        title: jogs ? 'Jogg/gange' : 'Rask gange, kupert',
        minutes: minutes,
        effort: Effort.moderat,
      );
    case SessionType.restitusjon:
      return Session(
        id: id,
        date: date,
        type: type,
        title: 'Rolig tur og tøying',
        minutes: deload ? 20 : 30,
        effort: Effort.lett,
      );
  }
}

/// Begrens økningen til maks 10 % fra forrige vanlige (hele) uke.
void enforceLoadCap(List<WeekPlan> weeks, {double cap = 0.10}) {
  WeekPlan? ref;
  for (final w in weeks) {
    if (w.deload) continue;
    if (ref != null && ref.sessions.length == w.sessions.length) {
      final limit = ref.load * (1 + cap);
      final adjustable = w.sessions
          .where((s) => s.type == SessionType.langtur || s.type == SessionType.kondisjon)
          .toList();
      var guard = 0;
      while (w.load > limit && guard++ < 40) {
        adjustable.sort((a, b) => b.minutes.compareTo(a.minutes));
        final s = adjustable.firstWhere((s) => s.minutes > 25, orElse: () => adjustable.first);
        if (s.minutes <= 25) break;
        s.minutes -= 5;
      }
    }
    ref = w;
  }
}

List<WeekPlan> generatePlan(Profile p) {
  final total = p.totalWeeks;
  final firstMonday = mondayOf(p.startDate);
  final weeks = <WeekPlan>[];
  var progression = 0;
  for (var i = 0; i < total; i++) {
    final monday = firstMonday.add(Duration(days: 7 * i));
    if (monday.isAfter(p.endDate)) break;
    final deload = isDeloadWeek(i, total);
    final w = WeekPlan(
      index: i,
      monday: monday,
      progression: deload ? max(0, progression - 1) : progression,
      deload: deload,
      phase: phaseFor(i, total),
      sessions: [],
    );
    w.sessions = sessionsForWeek(p, w);
    weeks.add(w);
    if (!deload) progression++;
  }
  enforceLoadCap(weeks);
  return weeks;
}

/// Bygg uker på nytt fra og med [fromIndex], med eventuell endring i progresjon.
void regenerateFrom(Profile p, List<WeekPlan> weeks, int fromIndex, {int progressionDelta = 0}) {
  for (final w in weeks.where((w) => w.index >= fromIndex)) {
    w.progression = max(0, w.progression + progressionDelta);
    w.sessions = sessionsForWeek(p, w);
  }
  enforceLoadCap(weeks);
}
