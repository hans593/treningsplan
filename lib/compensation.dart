// Forslag når en økt er stått over: flytt, fordel eller stryk.
//
// Regler:
// * Maks 10 % økning i ukentlig belastning.
// * Aldri to harde økter to dager på rad.
// * Tapte intervaller dobles aldri opp – de byttes til rolig økt om nødvendig.

import 'dart:math';

import 'models.dart';
import 'plan_generator.dart';

enum CompKind { flytt, fordel, stryk }

class PlanChange {
  final String dag;
  final String fra;
  final String til;
  const PlanChange(this.dag, this.fra, this.til);
}

class CompensationOption {
  final CompKind kind;
  final String title;
  final String description;
  final List<PlanChange> changes;
  final String summary;
  final bool recommended;
  final void Function(List<WeekPlan> weeks, Profile profile) _apply;

  CompensationOption({
    required this.kind,
    required this.title,
    required this.description,
    required this.changes,
    required this.summary,
    required this.recommended,
    required void Function(List<WeekPlan>, Profile) apply,
  }) : _apply = apply;

  void apply(List<WeekPlan> weeks, Profile profile, Session missed) {
    _apply(weeks, profile);
    missed.resolved = true;
    missed.resolution = switch (kind) {
      CompKind.flytt => Resolution.flyttet,
      CompKind.fordel => Resolution.fordelt,
      CompKind.stryk => Resolution.strokket,
    };
    missed.note = switch (kind) {
      CompKind.flytt => 'Flyttet',
      CompKind.fordel => 'Fordelt på neste uke',
      CompKind.stryk => 'Strøket',
    };
  }
}

Session? _sessionOn(List<WeekPlan> weeks, DateTime d) {
  for (final w in weeks) {
    for (final s in w.sessions) {
      if (s.date == dateOnly(d) && s.status != SessionStatus.staattOver) return s;
    }
  }
  return null;
}

bool _hardOn(List<WeekPlan> weeks, DateTime d) => _sessionOn(weeks, d)?.isHard ?? false;

WeekPlan? weekOf(List<WeekPlan> weeks, DateTime d) {
  for (final w in weeks) {
    if (w.contains(d)) return w;
  }
  return null;
}

/// Finn en ledig dag fra [from] til [to] for økta. Harde økter får ikke hard nabo.
DateTime? _findFreeDay(List<WeekPlan> weeks, DateTime from, DateTime to, {required bool hard}) {
  for (var d = dateOnly(from); !d.isAfter(to); d = d.add(const Duration(days: 1))) {
    if (_sessionOn(weeks, d) != null) continue;
    final prev = d.subtract(const Duration(days: 1));
    final next = d.add(const Duration(days: 1));
    if (hard && (_hardOn(weeks, prev) || _hardOn(weeks, next))) continue;
    return d;
  }
  return null;
}

List<CompensationOption> compensationOptions({
  required List<WeekPlan> weeks,
  required Profile profile,
  required Session missed,
  required DateTime today,
}) {
  final options = <CompensationOption>[];
  final week = weekOf(weeks, missed.date);
  if (week == null) return options;
  final nextWeek = weeks.where((w) => w.index == week.index + 1).firstOrNull;
  final t = dateOnly(today);

  // ---------- A: Flytt til ledig dag samme uke ----------
  final from = t.isAfter(missed.date) ? t : missed.date.add(const Duration(days: 1));
  final lastDay = week.sunday.isAfter(profile.endDate) ? profile.endDate : week.sunday;
  DateTime? day = _findFreeDay(weeks, from, lastDay, hard: missed.isHard);
  var convertToEasy = false;
  if (day == null && missed.isHard) {
    day = _findFreeDay(weeks, from, lastDay, hard: false);
    convertToEasy = day != null;
  }
  if (day != null) {
    final target = day;
    final nextHasSession = _sessionOn(weeks, target.add(const Duration(days: 1))) != null;
    var minutes = missed.minutes;
    var title = missed.title;
    var effort = missed.effort;
    String why;
    if (convertToEasy) {
      title = 'Rolig tur (erstatter intervaller)';
      minutes = min(40, missed.minutes);
      effort = Effort.lett;
      why = 'Intervaller kan ikke ligge inntil en annen hard økt, så den byttes til en rolig tur.';
    } else if (nextHasSession && missed.minutes >= 45) {
      minutes = max(30, ((missed.minutes * 0.85) / 5).round() * 5);
      why = '${_dagNavn(target)} er ledig. Økta kortes litt ned fordi det er trening dagen etter.';
    } else {
      why = '${_dagNavn(target)} er ledig.';
    }
    options.add(CompensationOption(
      kind: CompKind.flytt,
      title: 'Flytt til ${ukedager[target.weekday - 1]}',
      description: why,
      changes: [PlanChange(fmtUkedag(target), 'Hvile', '$title $minutes min')],
      summary: 'Uke ${week.index + 1}: alle øktene gjennomføres, belastning som planlagt.',
      recommended: true,
      apply: (ws, p) {
        final w = weekOf(ws, target)!;
        w.sessions.add(Session(
          id: '${missed.id}-flyttet',
          date: target,
          type: convertToEasy ? SessionType.restitusjon : missed.type,
          title: title,
          minutes: minutes,
          effort: effort,
          reps: convertToEasy ? 0 : missed.reps,
          workSec: convertToEasy ? 0 : missed.workSec,
          restSec: convertToEasy ? 0 : missed.restSec,
          rounds: missed.rounds,
          circuit: missed.circuit,
          note: 'Flyttet fra ${fmtUkedag(missed.date).toLowerCase()}',
        ));
        w.sessions.sort((a, b) => a.date.compareTo(b.date));
      },
    ));
  }

  // ---------- B: Fordel over neste uke ----------
  if (nextWeek != null && nextWeek.sessions.isNotEmpty) {
    final planned = nextWeek.load;
    var budget = planned * 0.10; // belastningsenheter
    var remaining = missed.minutes;
    final adds = <String, int>{}; // session id -> ekstra minutter
    final changes = <PlanChange>[];
    final candidates = nextWeek.sessions
        .where((s) => !s.isHard && s.type != SessionType.styrkeA && s.type != SessionType.styrkeB)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    for (final s in candidates) {
      if (remaining <= 0) break;
      final factor = s.load / s.minutes;
      final maxByBudget = ((budget / factor) / 5).floor() * 5;
      final add = min(min(15, maxByBudget), ((remaining + 4) ~/ 5) * 5);
      if (add <= 0) continue;
      adds[s.id] = add;
      budget -= add * factor;
      remaining -= add;
      changes.add(PlanChange(fmtUkedag(s.date), '${s.title} ${s.minutes} min', '${s.title} ${s.minutes + add} min'));
    }
    // Ekstra rolig tur på ledig dag hvis det er budsjett igjen.
    DateTime? extraDay;
    if (remaining >= 20 && budget >= 25) {
      extraDay = _findFreeDay(weeks, nextWeek.monday, nextWeek.sunday.subtract(const Duration(days: 1)), hard: false);
      if (extraDay != null) {
        final m = min(30, ((budget / 5).floor() * 5));
        changes.add(PlanChange(fmtUkedag(extraDay), 'Hvile', 'Rolig tur $m min'));
        budget -= m;
        adds['__extra__'] = m;
      }
    }
    if (changes.isNotEmpty) {
      final added = (planned * 0.10 - budget);
      final pct = (added / planned * 100).round();
      final ed = extraDay;
      options.add(CompensationOption(
        kind: CompKind.fordel,
        title: 'Fordel over neste uke',
        description: 'Litt lengre rolige økter neste uke, innenfor trygg økning.',
        changes: changes,
        summary: 'Uke ${nextWeek.index + 1}${nextWeek.deload ? ' (lettuke)' : ''}: +$pct % – under grensen på 10 %.',
        recommended: false,
        apply: (ws, p) {
          final w = ws.firstWhere((x) => x.index == nextWeek.index);
          for (final s in w.sessions) {
            final a = adds[s.id];
            if (a != null) {
              s.minutes += a;
              s.note = 'Lagt til $a min for tapt økt';
            }
          }
          if (ed != null) {
            w.sessions.add(Session(
              id: '${missed.id}-ekstra',
              date: ed,
              type: SessionType.restitusjon,
              title: 'Rolig tur',
              minutes: adds['__extra__']!,
              effort: Effort.lett,
              note: 'Erstatter tapt økt',
            ));
            w.sessions.sort((a, b) => a.date.compareTo(b.date));
          }
        },
      ));
    }
  }

  // ---------- C: Stryk og hold nivået ----------
  // Bare uker som ikke har startet bygges på nytt, så avkryssede økter beholdes.
  final firstFuture = weeks.where((w) => w.monday.isAfter(t)).firstOrNull?.index ?? weeks.length;
  final holdFrom = max(week.index + 1, firstFuture);
  options.add(CompensationOption(
    kind: CompKind.stryk,
    title: 'Stryk og fortsett',
    description: 'Ingen ekstra økter. Neste uke holdes på samme nivå i stedet for å øke.',
    changes: [
      if (holdFrom < weeks.length)
        PlanChange('Uke ${holdFrom + 1} og videre', 'Planlagt økning', 'Ett steg lavere progresjon')
      else
        const PlanChange('Resten av planen', 'Uendret', 'Uendret'),
    ],
    summary: 'Progresjonen flyttes én uke. Måldatoen er uendret.',
    recommended: options.isEmpty,
    apply: (ws, p) {
      if (holdFrom < ws.length) regenerateFrom(p, ws, holdFrom, progressionDelta: -1);
    },
  ));

  return options;
}

String _dagNavn(DateTime d) {
  final s = ukedager[d.weekday - 1];
  return '${s[0].toUpperCase()}${s.substring(1)}';
}

// ---------- Ekstra økter utenom planen ----------

/// Kan ekstraøkta erstatte den tapte økta?
/// Samme type (kondisjon/styrke), minst 70 % av tiden, og harde intervaller
/// må erstattes med noe mer enn en rolig tur. Økta må ligge i samme uke,
/// eller inntil 7 dager etter den tapte.
bool canCover(Session extra, Session missed, List<WeekPlan> weeks) {
  if (extra.category != missed.category) return false;
  if (extra.minutes < missed.minutes * 0.7) return false;
  if (missed.isHard && extra.effort == Effort.lett) return false;
  final diff = extra.date.difference(missed.date).inDays;
  final sameWeek = weekOf(weeks, extra.date) == weekOf(weeks, missed.date);
  return sameWeek || (diff > 0 && diff <= 7);
}

/// Kobler ubrukte ekstraøkter til tapte økter som ikke er håndtert.
/// Returnerer de tapte øktene som ble dekket.
List<Session> autoCover(List<WeekPlan> weeks) {
  final all = [for (final w in weeks) ...w.sessions];
  final open = all.where((s) => !s.extra && s.status == SessionStatus.staattOver && !s.resolved).toList();
  final free = all.where((s) => s.extra && s.covers == null).toList()..sort((a, b) => a.date.compareTo(b.date));
  final covered = <Session>[];
  for (final e in free) {
    final candidates = open.where((m) => canCover(e, m, weeks)).toList();
    if (candidates.isEmpty) continue;
    // Samme uke først, så samme type økt, deretter nærmeste dato.
    final ew = weekOf(weeks, e.date);
    candidates.sort((a, b) {
      final sa = weekOf(weeks, a.date) == ew ? 0 : 1, sb = weekOf(weeks, b.date) == ew ? 0 : 1;
      if (sa != sb) return sa - sb;
      final ta = a.type == e.type ? 0 : 1, tb = b.type == e.type ? 0 : 1;
      if (ta != tb) return ta - tb;
      return e.date.difference(a.date).inDays.abs().compareTo(e.date.difference(b.date).inDays.abs());
    });
    final m = candidates.first;
    open.remove(m);
    e.covers = m.id;
    e.note = 'Erstatter ${m.title.toLowerCase()} ${fmtDato(m.date)}';
    m.resolved = true;
    m.resolution = Resolution.ekstraOkt;
    m.note = 'Tatt igjen ${fmtDato(e.date)}';
    covered.add(m);
  }
  return covered;
}
