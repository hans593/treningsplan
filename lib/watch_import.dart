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

  /// GPS-punkter (tid, breddegrad, lengdegrad, høyde).
  final List<(DateTime, double, double, double?)> route;

  /// Health Connect har en rute, men appen har ikke lov til å lese den.
  final bool routeNeedsConsent;

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
    this.route = const [],
    this.routeNeedsConsent = false,
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

/// Avstand i meter mellom to punkter (haversine).
double metersBetween(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final p1 = lat1 * pi / 180, p2 = lat2 * pi / 180;
  final dp = (lat2 - lat1) * pi / 180, dl = (lng2 - lng1) * pi / 180;
  final a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2);
  return 2 * r * atan2(sqrt(a), sqrt(1 - a));
}

/// Gjør GPS-punktene om til en lagringsvennlig rute: maks [maxPoints] punkter
/// [bredde, lengde, pulssone], stigning (3 m terskel mot GPS-støy) og distanse.
({List<List<num>> points, int? ascentM, int? distanceM}) buildRoute(
    List<(DateTime, double, double, double?)> raw, List<(DateTime, double)> hrSorted, double hrMax,
    {int maxPoints = 250}) {
  final pts = [...raw]..sort((a, b) => a.$1.compareTo(b.$1));
  if (pts.length < 2) return (points: const [], ascentM: null, distanceM: null);
  var dist = 0.0;
  for (var i = 1; i < pts.length; i++) {
    dist += metersBetween(pts[i - 1].$2, pts[i - 1].$3, pts[i].$2, pts[i].$3);
  }
  double? ref;
  var ascent = 0.0;
  var hasAlt = false;
  for (final p in pts) {
    final alt = p.$4;
    if (alt == null) continue;
    hasAlt = true;
    if (ref == null) {
      ref = alt;
    } else if (alt > ref + 3) {
      ascent += alt - ref;
      ref = alt;
    } else if (alt < ref - 3) {
      ref = alt;
    }
  }
  final hr = [...hrSorted]..sort((a, b) => a.$1.compareTo(b.$1));
  int zoneAt(DateTime t) {
    if (hr.isEmpty) return -1;
    var lo = 0, hi = hr.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (hr[mid].$1.isAfter(t)) {
        hi = mid - 1;
      } else {
        lo = mid;
      }
    }
    if ((hr[lo].$1.difference(t).inSeconds).abs() > 180) return -1;
    final pct = hr[lo].$2 / hrMax;
    return pct < 0.6 ? 0 : pct < 0.7 ? 1 : pct < 0.8 ? 2 : pct < 0.9 ? 3 : 4;
  }

  final step = max(1, (pts.length / maxPoints).ceil());
  double r5(double v) => (v * 100000).round() / 100000;
  final out = <List<num>>[
    for (var i = 0; i < pts.length; i += step) [r5(pts[i].$2), r5(pts[i].$3), zoneAt(pts[i].$1)],
  ];
  if ((pts.length - 1) % step != 0) out.add([r5(pts.last.$2), r5(pts.last.$3), zoneAt(pts.last.$1)]);
  return (points: out, ascentM: hasAlt ? ascent.round() : null, distanceM: dist.round());
}

/// En måling over et tidsrom (skritt, distanse, kalorier) med kilde.
typedef Delta = (DateTime from, DateTime to, double value, String source);

/// Summen av målinger i tidsrommet [a]–[b] fra ÉN kilde.
/// Telefonen og Samsung Health registrerer ofte det samme (f.eks. distanse); summeres alle kilder,
/// telles det dobbelt. Vi bruker [prefer] (kilden til økta) når den har data, ellers kilden med mest.
/// Målinger som går over start eller slutt, tas med forholdsmessig.
int? sumOneSource(List<Delta> pts, DateTime a, DateTime b, {String prefer = ''}) {
  final bySource = <String, double>{};
  for (final (f, t, v, src) in pts) {
    final s0 = f.isAfter(a) ? f : a;
    final e0 = t.isBefore(b) ? t : b;
    if (!e0.isAfter(s0) && !(f == t && !f.isBefore(a) && !f.isAfter(b))) continue;
    final len = t.difference(f).inMilliseconds;
    final part = len <= 0 ? v : v * e0.difference(s0).inMilliseconds / len;
    bySource[src] = (bySource[src] ?? 0) + part;
  }
  if (bySource.isEmpty) return null;
  final chosen = bySource.containsKey(prefer) && bySource[prefer]! > 0
      ? bySource[prefer]!
      : bySource.values.reduce(max);
  return chosen <= 0 ? null : chosen.round();
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
  final rt = buildRoute(w.route, samples, hrMax);
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
    distanceM: w.distanceM ?? rt.distanceM,
    steps: w.steps,
    route: rt.points.length >= 2 ? [rt.points] : [],
    ascentM: rt.ascentM,
    routeNeedsConsent: w.routeNeedsConsent && rt.points.isEmpty,
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
    if (old != null) {
      data.outcome = old.outcome;
      data.mergedInto = old.mergedInto;
    }
    app.putWatchData(data);
    if (data.mergedInto != null) continue; // del av en sammenslått økt
    final day = dateOnly(w.start);
    if (app.importedWorkoutIds.contains(w.id)) {
      _linkExisting(app, data, day);
      continue;
    }
    _register(app, w, data, result, first);
  }
  refreshMerged(app);
  return result;
}

/// Legger én klokkeøkt inn i planen: kobler til, krysser av eller registrerer som ekstra.
void _register(AppState app, ImportedWorkout w, WatchData data, ImportResult result, DateTime first) {
  final p = app.profile!;
  final day = dateOnly(w.start);
  // For korte, utenfor planen eller i fremtiden: hopp over (men husk den).
  if (w.minutes < 10 || day.isBefore(first) || day.isAfter(app.today) || app.weekFor(day) == null) {
    data.outcome = w.minutes < 10
        ? 'Kortere enn 10 min – ikke regnet med (kan slås sammen med andre)'
        : day.isBefore(first)
            ? 'Før planen startet – ikke regnet med'
            : 'Utenfor planen';
    app.importedWorkoutIds.add(w.id);
    return;
  }
  final type = typeFor(w.activity);
  final effort = effortFor(w, p.age, maxHr: p.maxHr, ignoreHr: p.hrUnreliable);
  // Allerede krysset av for hånd samme dag: koble klokkedataene til den, ikke registrer på nytt.
  final manual = _doneWithoutWatch(app, day, type, w.minutes);
  if (manual != null) {
    manual.watchId = w.id;
    data.outcome = 'Koblet til «${manual.title}» (krysset av for hånd)';
    result.lines.add('${fmtUkedag(day)}: klokkedata koblet til «${manual.title}»');
    app.importedWorkoutIds.add(w.id);
    return;
  }
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

DateTime _firstPlanDay(AppState app) {
  final p = app.profile!;
  return app.weeks.first.monday.isBefore(p.startDate) ? p.startDate : app.weeks.first.monday;
}

WatchActivity _activityOf(String label) =>
    WatchActivity.values.firstWhere((a) => titleFor(a) == label, orElse: () => WatchActivity.annet);

/// Lager en «klokkeøkt» av lagrede data, så den kan legges inn i planen på nytt.
/// Varigheten er aktiv tid (viktig for sammenslåtte økter).
ImportedWorkout _asWorkout(WatchData d) => ImportedWorkout(
      id: d.id,
      start: d.start,
      end: d.start.add(Duration(seconds: d.durationSec)),
      activity: _activityOf(d.activity),
      avgHr: d.avgHr?.toDouble(),
      maxHr: d.maxHr?.toDouble(),
      kcal: d.kcal,
      distanceM: d.distanceM,
      steps: d.steps,
      source: d.source,
    );

/// Fjerner det en klokkeøkt gjorde i planen. Økter krysset av for hånd beholdes.
void _unlink(AppState app, WatchData d) {
  for (final s in app.weeks.expand((w) => w.sessions).where((s) => s.watchId == d.id).toList()) {
    if (s.extra) {
      app.deleteExtra(s);
    } else if (d.outcome.startsWith('Koblet til')) {
      s.watchId = null;
    } else {
      app.markNotDone(s);
      s.watchId = null;
    }
  }
  d.outcome = '';
}

/// Kan disse slås sammen? Returnerer feilmelding, eller null hvis det går.
String? canMergeWatch(List<WatchData> items) {
  if (items.length < 2) return 'Velg minst to økter.';
  if (items.any((d) => d.isMerged || d.mergedInto != null)) return 'En av øktene er allerede slått sammen.';
  final day = dateOnly(items.first.start);
  if (items.any((d) => dateOnly(d.start) != day)) return 'Bare økter fra samme dag kan slås sammen.';
  return null;
}

/// Slår sammen korte klokkeøkter fra samme dag til én.
/// Tid, distanse, skritt, kalorier og pulssoner summeres; snittpuls vektes etter tid.
/// Det delene gjorde i planen fjernes, og den samlede økta legges inn på nytt.
ImportResult mergeWatchWorkouts(AppState app, List<String> ids) {
  final result = ImportResult();
  final items = [for (final id in ids) app.watchDataById(id)].whereType<WatchData>().toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final err = canMergeWatch(items);
  if (err != null) {
    result.lines.add(err);
    return result;
  }
  for (final d in items) {
    _unlink(app, d);
  }
  final merged = combineWatch(items, 'sammen:${items.first.id}:${items.length}');
  for (final d in items) {
    d.mergedInto = merged.id;
    d.outcome = 'Slått sammen med ${items.length - 1} andre';
  }
  app.putWatchData(merged);
  _register(app, _asWorkout(merged), merged, result, _firstPlanDay(app));
  return result;
}

/// Regner ut den samlede økta av delene.
/// Overlapper delene i tid (f.eks. en tur som både ble oppdaget automatisk og startet på klokka),
/// telles bare tiden som ikke alt er dekket, og distanse, skritt, kalorier og pulssoner skaleres likt.
WatchData combineWatch(List<WatchData> parts, String id, {String outcome = ''}) {
  final items = [...parts]..sort((a, b) => a.start.compareTo(b.start));
  final frac = <double>[];
  DateTime? coveredEnd;
  for (final d in items) {
    final full = d.end.difference(d.start).inSeconds;
    final from = coveredEnd != null && coveredEnd.isAfter(d.start) ? coveredEnd : d.start;
    final unique = d.end.isAfter(from) ? d.end.difference(from).inSeconds : 0;
    frac.add(full <= 0 ? 0 : unique / full);
    if (coveredEnd == null || d.end.isAfter(coveredEnd)) coveredEnd = d.end;
  }
  double sec(int i) => items[i].durationSec * frac[i];
  final active = [for (var i = 0; i < items.length; i++) sec(i)].fold<double>(0, (a, b) => a + b).round();
  int? sum(int? Function(WatchData) f) {
    var any = false;
    var t = 0.0;
    for (var i = 0; i < items.length; i++) {
      final v = f(items[i]);
      if (v == null) continue;
      any = true;
      t += v * frac[i];
    }
    return any ? t.round() : null;
  }

  var hrSec = 0.0, hrSum = 0.0;
  for (var i = 0; i < items.length; i++) {
    if (items[i].avgHr == null) continue;
    hrSec += sec(i);
    hrSum += items[i].avgHr! * sec(i);
  }
  final byAct = <String, double>{};
  for (var i = 0; i < items.length; i++) {
    byAct[items[i].activity] = (byAct[items[i].activity] ?? 0) + sec(i);
  }
  final activity = (byAct.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  final used = [for (var i = 0; i < items.length; i++) if (frac[i] > 0) items[i]];
  return WatchData(
    id: id,
    start: items.first.start,
    end: items.map((d) => d.end).reduce((a, b) => a.isAfter(b) ? a : b),
    activity: activity,
    source: items.first.source,
    avgHr: hrSec == 0 ? null : (hrSum / hrSec).round(),
    maxHr: used.map((d) => d.maxHr).whereType<int>().fold<int?>(null, (a, b) => a == null || b > a ? b : a),
    minHr: used.map((d) => d.minHr).whereType<int>().fold<int?>(null, (a, b) => a == null || b < a ? b : a),
    kcal: sum((d) => d.kcal),
    distanceM: sum((d) => d.distanceM),
    steps: sum((d) => d.steps),
    zoneSec: [
      for (var z = 0; z < 5; z++)
        [for (var i = 0; i < items.length; i++) (z < items[i].zoneSec.length ? items[i].zoneSec[z] : 0) * frac[i]]
            .fold<double>(0, (a, b) => a + b)
            .round()
    ],
    hrCurve: [
      for (var i = 0; i < used.length; i++) ...[if (i > 0) 0, ...used[i].hrCurve]
    ],
    hrMaxUsed: items.first.hrMaxUsed,
    parts: [for (final d in items) d.id],
    activeSec: active,
    outcome: outcome,
    route: [for (final d in used) ...d.route],
    ascentM: used.any((d) => d.ascentM != null) ? used.fold<int>(0, (a, d) => a + (d.ascentM ?? 0)) : null,
    routeNeedsConsent: used.any((d) => d.routeNeedsConsent),
  );
}

/// Etter ny henting: regn ut sammenslåtte økter på nytt fra de oppdaterte delene.
void refreshMerged(AppState app) {
  for (final m in app.watchLog.where((d) => d.isMerged).toList()) {
    final parts = [for (final id in m.parts) app.watchDataById(id)].whereType<WatchData>().toList();
    if (parts.length != m.parts.length) continue;
    app.putWatchData(combineWatch(parts, m.id, outcome: m.outcome));
  }
}

/// Deler en sammenslått økt opp igjen; hver del legges inn i planen for seg.
ImportResult splitWatchWorkout(AppState app, String mergedId) {
  final result = ImportResult();
  final m = app.watchDataById(mergedId);
  if (m == null || !m.isMerged) return result;
  _unlink(app, m);
  app.watchLog.removeWhere((d) => d.id == m.id);
  app.importedWorkoutIds.remove(m.id);
  final first = _firstPlanDay(app);
  for (final id in m.parts) {
    final d = app.watchDataById(id);
    if (d == null) continue;
    d.mergedInto = null;
    d.outcome = '';
    _register(app, _asWorkout(d), d, result, first);
  }
  return result;
}

/// Fullført økt samme dag og kategori som ennå ikke har klokkedata (krysset av for hånd).
Session? _doneWithoutWatch(AppState app, DateTime day, SessionType type, int minutes) {
  final c = (app.weekFor(day)?.sessions ?? const <Session>[])
      .where((s) =>
          s.date == day &&
          s.watchId == null &&
          s.status == SessionStatus.fullfort &&
          s.category == categoryOf(type))
      .toList()
    ..sort((a, b) {
      // Planlagte økter før ekstra, deretter nærmest i tid.
      final e = (a.extra ? 1 : 0) - (b.extra ? 1 : 0);
      return e != 0 ? e : (a.minutes - minutes).abs() - (b.minutes - minutes).abs();
    });
  return c.firstOrNull;
}

/// Økter hentet før klokkedata ble lagret: koble dem til økta de krysset av samme dag
/// («Fra klokka» først, ellers en økt krysset av for hånd).
void _linkExisting(AppState app, WatchData data, DateTime day) {
  final all = app.weeks.expand((w) => w.sessions);
  if (all.any((s) => s.watchId == data.id)) return;
  final candidates = all
      .where((s) => s.date == day && s.watchId == null && (s.note ?? '').toLowerCase().contains('fra klokka'))
      .toList()
    ..sort((a, b) => (a.minutes - data.minutes).abs() - (b.minutes - data.minutes).abs());
  final type = all.where((s) => s.date == day).isEmpty ? null : typeFor(_activityOf(data.activity));
  final s = candidates.firstOrNull ?? (type == null ? null : _doneWithoutWatch(app, day, type, data.minutes));
  if (s == null) return;
  s.watchId = data.id;
  if (data.outcome.isEmpty || data.outcome.startsWith('Før planen')) {
    data.outcome = s.extra
        ? 'Registrert som ekstra økt'
        : (s.note ?? '').toLowerCase().contains('fra klokka')
            ? 'Krysset av «${s.title}»'
            : 'Koblet til «${s.title}» (krysset av for hånd)';
  }
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
