// Gjør økter fra klokka (via Health Connect) om til avkryssede eller ekstra økter.
// Ren logikk uten plattformkall, så den kan testes.

import 'dart:math';

import 'models.dart';
import 'state.dart';

enum WatchActivity { gange, lop, sykling, ski, kondisjon, intervall, styrke, annet }

class ImportedWorkout {
  final String id;
  final DateTime start;
  final DateTime end;
  final WatchActivity activity;
  final double? avgHr;
  final double? maxHr;
  final int? kcal;
  final int? distanceM;
  final int? steps;
  final String source;

  /// Pulsmålinger under økta (tid, slag per minutt).
  final List<(DateTime, double)> hrSamples;

  const ImportedWorkout({
    required this.id,
    required this.start,
    required this.end,
    required this.activity,
    this.avgHr,
    this.maxHr,
    this.kcal,
    this.distanceM,
    this.steps,
    this.source = '',
    this.hrSamples = const [],
  });

  int get minutes => end.difference(start).inMinutes;
}

class ImportResult {
  final List<String> lines = [];
  int markedDone = 0;
  int extras = 0;
  int covered = 0;
  int weights = 0;

  bool get isEmpty => markedDone == 0 && extras == 0 && weights == 0;

  String get summary {
    final parts = <String>[
      if (markedDone > 0) '$markedDone planlagte krysset av',
      if (extras > 0) '$extras ekstra',
      if (covered > 0) '$covered tapte tatt igjen',
      if (weights > 0) '$weights vektmålinger',
    ];
    return parts.isEmpty ? 'Ingen nye økter fra klokka' : 'Fra klokka: ${parts.join(', ')}';
  }
}

/// Gjør pulsmålingene om til det som vises: snitt, maks, tid i soner og en kurve per minutt.
/// Hver måling gjelder fram til neste (maks 2 min, så hull i målingene ikke teller).
WatchData watchDataFor(ImportedWorkout w, double hrMax) {
  final samples = w.hrSamples
      .where((x) => x.$2 > 30 && x.$2 < 230 && !x.$1.isBefore(w.start) && !x.$1.isAfter(w.end))
      .toList()
    ..sort((a, b) => a.$1.compareTo(b.$1));
  final zones = [0, 0, 0, 0, 0];
  final minutes = max(1, (w.end.difference(w.start).inSeconds / 60).ceil());
  final sum = List<double>.filled(minutes, 0);
  final cnt = List<int>.filled(minutes, 0);
  for (var i = 0; i < samples.length; i++) {
    final (t, bpm) = samples[i];
    final next = i + 1 < samples.length ? samples[i + 1].$1 : w.end;
    final sec = min(120, max(1, next.difference(t).inSeconds));
    final pct = bpm / hrMax;
    final z = pct < 0.6 ? 0 : pct < 0.7 ? 1 : pct < 0.8 ? 2 : pct < 0.9 ? 3 : 4;
    zones[z] += sec;
    final m = min(minutes - 1, t.difference(w.start).inSeconds ~/ 60);
    sum[m] += bpm;
    cnt[m]++;
  }
  final bpms = samples.map((x) => x.$2).toList();
  // Bruk tidsvektet snitt når vi har målinger, ellers det Health Connect oppga.
  double? avg = w.avgHr;
  if (bpms.isNotEmpty) {
    var tot = 0.0, secs = 0;
    for (var i = 0; i < samples.length; i++) {
      final next = i + 1 < samples.length ? samples[i + 1].$1 : w.end;
      final sec = min(120, max(1, next.difference(samples[i].$1).inSeconds));
      tot += samples[i].$2 * sec;
      secs += sec;
    }
    avg = tot / secs;
  }
  return WatchData(
    id: w.id,
    start: w.start,
    end: w.end,
    activity: titleFor(w.activity),
    source: w.source,
    avgHr: avg?.round(),
    maxHr: bpms.isNotEmpty ? bpms.reduce(max).round() : w.maxHr?.round(),
    minHr: bpms.isNotEmpty ? bpms.reduce(min).round() : null,
    kcal: w.kcal,
    distanceM: w.distanceM,
    steps: w.steps,
    zoneSec: zones,
    hrCurve: [for (var m = 0; m < minutes; m++) cnt[m] == 0 ? 0 : (sum[m] / cnt[m]).round()],
    hrMaxUsed: hrMax.round(),
  );
}

/// Makspuls anslått ut fra alder (Tanaka: 208 − 0,7 × alder).
double maxHrFor(int age) => 208 - 0.7 * age;

SessionType typeFor(WatchActivity a) => switch (a) {
      WatchActivity.gange => SessionType.langtur,
      WatchActivity.intervall => SessionType.motbakke,
      WatchActivity.styrke => SessionType.styrkeA,
      WatchActivity.annet => SessionType.restitusjon,
      _ => SessionType.kondisjon,
    };

String titleFor(WatchActivity a) => switch (a) {
      WatchActivity.gange => 'Gåtur',
      WatchActivity.lop => 'Løping',
      WatchActivity.sykling => 'Sykling',
      WatchActivity.ski => 'Langrenn / ski',
      WatchActivity.kondisjon => 'Kondisjonstrening',
      WatchActivity.intervall => 'Intervaller',
      WatchActivity.styrke => 'Styrketrening',
      WatchActivity.annet => 'Annen aktivitet',
    };

/// Anstrengelse ut fra puls når den finnes, ellers ut fra aktivitet.
/// Høy makspuls under gange eller løping tolkes som intervaller (f.eks. motbakker).
Effort effortFor(ImportedWorkout w, int age, {int? maxHr, bool ignoreHr = false}) {
  final hrMax = (maxHr ?? maxHrFor(age)).toDouble();
  if (ignoreHr) {
    // Medisin påvirker pulsen: bruk bare aktiviteten.
    return switch (w.activity) {
      WatchActivity.gange || WatchActivity.annet => Effort.lett,
      WatchActivity.intervall => Effort.hard,
      _ => Effort.moderat,
    };
  }
  if (w.maxHr != null && w.maxHr! >= hrMax * 0.85 && w.minutes >= 20 &&
      (w.activity == WatchActivity.gange || w.activity == WatchActivity.lop || w.activity == WatchActivity.intervall)) {
    return Effort.hard;
  }
  if (w.avgHr != null && w.avgHr! > 40) {
    final pct = w.avgHr! / hrMax;
    if (pct < 0.64) return Effort.lett;
    if (pct < 0.77) return Effort.moderat;
    return Effort.hard;
  }
  return switch (w.activity) {
    WatchActivity.gange || WatchActivity.annet => Effort.lett,
    WatchActivity.intervall => Effort.hard,
    _ => Effort.moderat,
  };
}

String _detail(ImportedWorkout w) {
  final parts = <String>['${w.minutes} min'];
  if (w.distanceM != null && w.distanceM! > 0) {
    parts.add('${(w.distanceM! / 1000).toStringAsFixed(1).replaceAll('.', ',')} km');
  }
  if (w.avgHr != null) parts.add('snittpuls ${w.avgHr!.round()}');
  return parts.join(' · ');
}

/// Finn planlagt økt samme dag som økta fra klokka kan krysse av.
/// Samme slag (kondisjon/styrke), minst halvparten av tiden, og harde økter
/// må ha vært mer enn en rolig tur.
Session? _matchPlanned(AppState app, ImportedWorkout w, SessionType type, Effort effort) {
  final day = dateOnly(w.start);
  final candidates = (app.weekFor(day)?.sessions ?? const <Session>[])
      .where((s) =>
          !s.extra &&
          s.date == day &&
          s.category == categoryOf(type) &&
          (s.status == SessionStatus.planlagt || s.canBackRegister) &&
          w.minutes >= s.minutes * 0.5 &&
          !(s.isHard && effort == Effort.lett))
      .toList()
    // Samme type foretrekkes (f.eks. intervaller → motbakkeøkta).
    ..sort((a, b) => (a.type == type ? 0 : 1) - (b.type == type ? 0 : 1));
  return candidates.firstOrNull;
}

ImportResult applyWorkouts(AppState app, List<ImportedWorkout> workouts) {
  final result = ImportResult();
  final p = app.profile;
  if (p == null || app.weeks.isEmpty) return result;
  final first = app.weeks.first.monday.isBefore(p.startDate) ? p.startDate : app.weeks.first.monday;

  final hrMax = (p.maxHr ?? maxHrFor(p.age)).toDouble();
  final sorted = [...workouts]..sort((a, b) => a.start.compareTo(b.start));
  for (final w in sorted) {
    // Det klokka registrerte, lagres alltid (også økter som ikke påvirker planen).
    final data = watchDataFor(w, hrMax);
    final old = app.watchLog.where((x) => x.id == w.id).firstOrNull;
    if (old != null) data.outcome = old.outcome;
    app.putWatchData(data);
    final day = dateOnly(w.start);
    if (app.importedWorkoutIds.contains(w.id)) {
      _linkExisting(app, data, day);
      continue;
    }
    // For korte, utenfor planen eller i fremtiden: hopp over (men husk den).
    if (w.minutes < 10 || day.isBefore(first) || day.isAfter(app.today) || app.weekFor(day) == null) {
      data.outcome = w.minutes < 10
          ? 'Kortere enn 10 min – ikke regnet med'
          : day.isBefore(first)
              ? 'Før planen startet – ikke regnet med'
              : 'Utenfor planen';
      app.importedWorkoutIds.add(w.id);
      continue;
    }
    final type = typeFor(w.activity);
    final effort = effortFor(w, p.age, maxHr: p.maxHr, ignoreHr: p.hrUnreliable);
    final planned = _matchPlanned(app, w, type, effort);
    if (planned != null) {
      if (planned.status == SessionStatus.planlagt) {
        app.markDone(planned);
      } else {
        app.backRegister(planned);
      }
      planned.note = 'Fra klokka: ${_detail(w)}';
      planned.watchId = w.id;
      data.outcome = 'Krysset av «${planned.title}»';
      result.markedDone++;
      result.lines.add('${fmtUkedag(day)}: «${planned.title}» krysset av (${_detail(w)})');
    } else {
      final covered = app.addExtra(
        date: day,
        type: type,
        title: titleFor(w.activity),
        minutes: max(10, w.minutes),
        effort: effort,
      );
      final extra = app.weekFor(day)!.sessions.lastWhere((s) => s.extra && s.date == day);
      extra.note = extra.covers != null ? '${extra.note} · fra klokka' : 'Fra klokka: ${_detail(w)}';
      extra.watchId = w.id;
      data.outcome = 'Registrert som ekstra økt${covered.isNotEmpty ? ' – tar igjen «${covered.first.title}»' : ''}';
      result.extras++;
      result.covered += covered.length;
      result.lines.add('${fmtUkedag(day)}: ${titleFor(w.activity)} registrert som ekstra (${_detail(w)})'
          '${covered.isNotEmpty ? ' – tar igjen «${covered.first.title}»' : ''}');
    }
    app.importedWorkoutIds.add(w.id);
  }
  return result;
}

/// Økter hentet før klokkedata ble lagret: koble dem til økta de krysset av (samme dag, «Fra klokka»).
void _linkExisting(AppState app, WatchData data, DateTime day) {
  final all = app.weeks.expand((w) => w.sessions);
  if (all.any((s) => s.watchId == data.id)) return;
  final candidates = all
      .where((s) => s.date == day && s.watchId == null && (s.note ?? '').toLowerCase().contains('fra klokka'))
      .toList()
    ..sort((a, b) => (a.minutes - data.minutes).abs() - (b.minutes - data.minutes).abs());
  final s = candidates.firstOrNull;
  if (s == null) return;
  s.watchId = data.id;
  if (data.outcome.isEmpty) data.outcome = s.extra ? 'Registrert som ekstra økt' : 'Krysset av «${s.title}»';
}

/// Vekt fra smartvekt via Samsung Health. Én måling per dag (den siste).
int applyWeights(AppState app, List<(DateTime, double)> weights) {
  final byDay = <DateTime, double>{};
  for (final (t, kg) in [...weights]..sort((a, b) => a.$1.compareTo(b.$1))) {
    if (kg < 30 || kg > 300) continue;
    byDay[dateOnly(t)] = kg;
  }
  var added = 0;
  for (final e in byDay.entries) {
    if (app.measurements.any((m) => m.date == e.key && m.weightKg != null)) continue;
    final waist = app.measurements.where((m) => m.date == e.key).firstOrNull?.waistCm;
    app.addMeasurementSilently(Measurement(date: e.key, weightKg: e.value, waistCm: waist));
    added++;
  }
  return added;
}
