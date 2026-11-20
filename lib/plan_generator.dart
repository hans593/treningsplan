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

/// Standard treningsdager (0 = mandag) for 3–6 dager i uka.
List<int> defaultDays(int daysPerWeek) => switch (daysPerWeek.clamp(3, 6)) {
      3 => [0, 2, 5],
      4 => [0, 1, 3, 5],
      5 => [0, 1, 2, 3, 5],
      _ => [0, 1, 2, 3, 4, 5],
    };

/// Økttyper for antall dager, viktigst først.
List<SessionType> sessionTypesFor(int n) => [
      SessionType.motbakke,
      SessionType.styrkeA,
      SessionType.langtur,
      if (n >= 4) SessionType.styrkeB,
      if (n >= 5) SessionType.kondisjon,
      if (n >= 6) SessionType.restitusjon,
    ];

/// Fordel økttypene på valgte dager:
/// intervaller helst med hviledag etter, langtur helst i helga,
/// og de to styrkeøktene ikke to dager på rad.
Map<int, SessionType> assignDays(List<int> days) {
  final d = ([...days.toSet()]..sort()).take(6).toList();
  final types = sessionTypesFor(d.length);
  bool chosen(int x) => d.contains((x + 7) % 7);
  int score(List<int> perm) {
    var sc = 0;
    final at = {for (var i = 0; i < types.length; i++) types[i]: perm[i]};
    final hard = at[SessionType.motbakke]!;
    if (!chosen(hard + 1)) sc += 4; // hvile etter intervaller
    if (!chosen(hard - 1)) sc += 1;
    final lang = at[SessionType.langtur]!;
    if (lang >= 5) sc += 3; // langtur i helga
    final a = at[SessionType.styrkeA]!, b = at[SessionType.styrkeB];
    if (b != null && ((a - b).abs() == 1 || (a - b).abs() == 6)) sc -= 3;
    if (b != null && (a - b).abs() >= 2) sc += 1;
    if (hard <= 2) sc += 1; // intervaller tidlig i uka
    return sc;
  }

  List<int>? best;
  var bestScore = -1 << 30;
  void permute(List<int> rest, List<int> acc) {
    if (acc.length == types.length) {
      final sc = score(acc);
      if (sc > bestScore) {
        bestScore = sc;
        best = List.of(acc);
      }
      return;
    }
    for (final x in rest) {
      permute(rest.where((y) => y != x).toList(), [...acc, x]);
    }
  }

  permute(d.take(types.length).toList(), []);
  return {for (var i = 0; i < types.length; i++) best![i]: types[i]};
}

/// Standardmaler (brukes når brukeren ikke har valgt dager selv).
Map<int, SessionType> legacyTemplate(int daysPerWeek) => switch (daysPerWeek.clamp(3, 6)) {
      3 => {0: SessionType.motbakke, 2: SessionType.styrkeA, 5: SessionType.langtur},
      4 => {0: SessionType.motbakke, 1: SessionType.styrkeA, 3: SessionType.styrkeB, 5: SessionType.langtur},
      5 => {
          0: SessionType.motbakke,
          1: SessionType.styrkeA,
          2: SessionType.langtur,
          3: SessionType.styrkeB,
          5: SessionType.kondisjon,
        },
      _ => {
          0: SessionType.motbakke,
          1: SessionType.styrkeA,
          2: SessionType.langtur,
          3: SessionType.styrkeB,
          4: SessionType.restitusjon,
          5: SessionType.kondisjon,
        },
    };

/// Ukemal for profilen: ukedag (0 = mandag) -> økttype.
Map<int, SessionType> weekTemplate(Profile p) {
  final days = p.trainingDays;
  if (days != null && days.length >= 3) {
    final sorted = [...days.toSet()]..sort();
    // Samme dager som standard: bruk standardfordelingen.
    final def = legacyTemplate(sorted.length);
    if (listEquals(sorted, def.keys.toList()..sort())) return def;
    return assignDays(sorted);
  }
  return legacyTemplate(p.daysPerWeek);
}

bool listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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
  final template = weekTemplate(p);
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
          title: p.has(Activity.manualer) ? 'Styrke A – manualer' : 'Styrke A – kroppsvekt',
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

/// Forrige vanlige (ikke lette) uke før [w], eller null.
/// Første uke regnes ikke som referanse hvis den bare er delvis (planen starter midt i uka).
WeekPlan? referenceWeek(List<WeekPlan> weeks, WeekPlan w, {DateTime? startDate}) {
  for (var i = w.index - 1; i >= 0; i--) {
    final r = weeks[i];
    if (r.deload) continue;
    if (i == 0 && startDate != null && r.monday.isBefore(startDate)) return null;
    if (r.plannedCount == 0) continue;
    return r;
  }
  return null;
}

/// Største tillatte planlagte belastning for uka:
/// maks 10 % over forrige vanlige uke, og lettuker aldri over 90 % av den.
double? loadLimit(List<WeekPlan> weeks, WeekPlan w, {DateTime? startDate, double cap = 0.10}) {
  final ref = referenceWeek(weeks, w, startDate: startDate);
  if (ref == null) return null;
  return ref.plannedLoad * (w.deload ? 0.9 : 1 + cap);
}

/// Hvor mange økter som må være igjen i en uke.
const _minSessions = 3;
const _removeOrder = [SessionType.restitusjon, SessionType.kondisjon, SessionType.styrkeB, SessionType.langtur];

/// Hold hver uke fra og med [fromIndex] innenfor 10 %-grensen.
/// Først kortes rolige økter litt, så kortes øktene ned mot minimum, og bare hvis det
/// ikke er nok, fjernes økter (lavest prioritet først). Gjennomførte økter og ekstraøkter røres ikke.
void enforceLoadCap(List<WeekPlan> weeks, {int fromIndex = 0, DateTime? startDate, double cap = 0.10}) {
  for (final w in weeks.where((w) => w.index >= fromIndex)) {
    final limit = loadLimit(weeks, w, startDate: startDate, cap: cap);
    if (limit == null) continue;
    bool editable(Session s) => !s.extra && s.status == SessionStatus.planlagt;
    final easy = w.sessions
        .where((s) => editable(s) && (s.type == SessionType.langtur || s.type == SessionType.kondisjon || s.type == SessionType.restitusjon))
        .toList();
    final floor80 = {for (final s in easy) s.id: max(20, (s.minutes * 0.8 / 5).round() * 5)};
    var guard = 0;
    // 1) Korte rolige økter ned til 80 %.
    while (w.plannedLoad > limit && guard++ < 60) {
      final c = easy.where((s) => s.minutes - 5 >= floor80[s.id]!).toList()
        ..sort((a, b) => b.minutes.compareTo(a.minutes));
      if (c.isEmpty) break;
      c.first.minutes -= 5;
    }
    // 2) Kort ned til minimum: rolige økter 20 min, styrke 2 runder, intervaller 3 drag.
    guard = 0;
    while (w.plannedLoad > limit && guard++ < 80) {
      final s = w.sessions.where(editable).toList()..sort((a, b) => b.load.compareTo(a.load));
      var changed = false;
      for (final x in s) {
        if ((x.type == SessionType.styrkeA || x.type == SessionType.styrkeB) && x.rounds > 2) {
          x.rounds -= 1;
          x.minutes = max(20, x.minutes - (x.type == SessionType.styrkeA ? 10 : 5));
          changed = true;
        } else if (x.type == SessionType.motbakke && x.reps > 3) {
          x.reps -= 1;
          x.minutes = max(30, x.minutes - ((x.workSec + x.restSec) / 60).round());
          changed = true;
        } else if (x.minutes > 20 && x.type != SessionType.motbakke) {
          x.minutes -= 5;
          changed = true;
        }
        if (changed) break;
      }
      if (!changed) break;
    }
    // 3) Fortsatt for mye: fjern økter, lavest prioritet først (gir gradvis opptrapping av antall dager).
    for (final t in _removeOrder) {
      if (w.plannedLoad <= limit) break;
      if (w.plannedCount <= _minSessions) break;
      final victim = w.sessions.where((s) => editable(s) && s.type == t).firstOrNull;
      if (victim != null) w.sessions.remove(victim);
    }
  }
}

/// Brudd på trygghetsreglene i planen fra og med [fromIndex] (brukes i tester og kontroll).
List<String> safetyViolations(List<WeekPlan> weeks, {int fromIndex = 0, DateTime? startDate}) {
  final out = <String>[];
  for (final w in weeks.where((w) => w.index >= fromIndex)) {
    final limit = loadLimit(weeks, w, startDate: startDate);
    if (limit != null && w.plannedLoad > limit + 0.01) {
      out.add('Uke ${w.index + 1}: belastning ${w.plannedLoad.toStringAsFixed(0)} over grensen ${limit.toStringAsFixed(0)}');
    }
  }
  final hard = [
    for (final w in weeks)
      for (final s in w.sessions)
        if (s.isHard && s.status != SessionStatus.staattOver) s.date
  ]..sort();
  for (var i = 1; i < hard.length; i++) {
    if (hard[i].difference(hard[i - 1]).inDays <= 1) out.add('Harde økter dager på rad: ${hard[i - 1]} og ${hard[i]}');
  }
  return out;
}

/// Gjør en økt lettere for dagen. Bare nedover – aldri tyngre.
void applyEase(Session s, Ease e) {
  if (s.ease != null) return;
  switch (e) {
    case Ease.kortere:
      switch (s.type) {
        case SessionType.styrkeA:
        case SessionType.styrkeB:
          final r = max(1, s.rounds - 1);
          final cut = s.rounds - r;
          s.rounds = r;
          s.minutes = max(15, s.minutes - cut * (s.type == SessionType.styrkeA ? 10 : 5));
        case SessionType.motbakke:
          final r = max(2, s.reps - 2);
          s.minutes = max(25, s.minutes - ((s.reps - r) * (s.workSec + s.restSec) / 60).round());
          s.reps = r;
        default:
          s.minutes = max(15, ((s.minutes * 0.66) / 5).round() * 5);
      }
      s.note = 'Kortere i dag';
    case Ease.rolig:
      s.type = SessionType.restitusjon;
      s.title = 'Rolig tur (lettere i dag)';
      s.minutes = min(30, s.minutes);
      s.effort = Effort.lett;
      s.reps = 0;
      s.workSec = 0;
      s.restSec = 0;
      s.note = 'Byttet til rolig tur';
  }
  s.ease = e;
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
  enforceLoadCap(weeks, startDate: p.startDate);
  return weeks;
}

/// Er økta lagt til av kompensasjon (flyttet eller ekstra rolig tur)?
bool isCompensationSession(Session s) => s.id.endsWith('-flyttet') || s.id.endsWith('-ekstra');

/// Bygg uker på nytt fra og med [fromIndex], med eventuell endring i progresjon.
/// Det brukeren selv har gjort, beholdes: avkryssede og håndterte økter, ekstraøkter,
/// flyttede økter (ny dag), minutter lagt til for tapte økter, og «lettere i dag».
void regenerateFrom(Profile p, List<WeekPlan> weeks, int fromIndex, {int progressionDelta = 0}) {
  for (final w in weeks.where((w) => w.index >= fromIndex)) {
    w.progression = max(0, w.progression + progressionDelta);
    final old = {for (final s in w.sessions) s.id: s};
    final fresh = <Session>[];
    for (final f in sessionsForWeek(p, w)) {
      final o = old.remove(f.id);
      if (o == null) {
        fresh.add(f);
      } else if (o.status != SessionStatus.planlagt) {
        fresh.add(o); // gjort, tapt eller håndtert: røres ikke
      } else {
        if (w.contains(o.date)) f.date = o.date; // flyttet av brukeren
        if (o.addedMin > 0) {
          f.addedMin = o.addedMin;
          f.minutes += o.addedMin;
          f.note = o.note;
        }
        if (o.ease != null) applyEase(f, o.ease!);
        fresh.add(f);
      }
    }
    // Behold ekstraøkter, kompensasjonsøkter og økter som er gjort/håndtert.
    for (final o in old.values) {
      if (o.extra || isCompensationSession(o) || o.status != SessionStatus.planlagt) fresh.add(o);
    }
    fresh.sort((a, b) => a.date.compareTo(b.date));
    w.sessions = fresh;
  }
  enforceLoadCap(weeks, fromIndex: fromIndex, startDate: p.startDate);
}
