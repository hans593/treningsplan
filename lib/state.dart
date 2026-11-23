// App-tilstand med lagring på telefonen (fungerer uten nett).

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'compensation.dart';
import 'models.dart';
import 'move.dart';
import 'plan_generator.dart';
import 'watch_import.dart';

/// Hvor mange nivåsteg planen settes ned etter fravær av en gitt lengde.
/// 99 betyr tilbake til start (tilvenning).
int absenceSteps(int days) {
  if (days < 7) return 0;
  if (days < 14) return 1;
  if (days < 28) return 2;
  if (days < 42) return 3;
  return 99;
}

/// Gyldige grenser for målinger.
const minKg = 35.0, maxKg = 250.0, minWaist = 40.0, maxWaist = 200.0;

String? validateWeight(double? kg) =>
    kg == null || (kg >= minKg && kg <= maxKg) ? null : 'Vekt må være mellom ${minKg.round()} og ${maxKg.round()} kg';
String? validateWaist(double? cm) =>
    cm == null || (cm >= minWaist && cm <= maxWaist) ? null : 'Midjemål må være mellom ${minWaist.round()} og ${maxWaist.round()} cm';

class AppState extends ChangeNotifier {
  AppState({DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  final DateTime Function() clock;
  static const _key = 'treningsplan_v1';

  Profile? profile;
  List<WeekPlan> weeks = [];
  List<Measurement> measurements = [];
  List<TestResult> tests = [];
  DateTime? lastSetback;
  bool loaded = false;

  /// Uke (indeks) der nivået sist ble satt ned av «stryk» eller tilbakesteg – maks én gang per uke.
  int? holdWeek;

  /// Fravær (sykdom, ferie, skade).
  List<Absence> absences = [];

  /// Endringer i nivået, med forklaring som vises til brukeren.
  List<LevelChange> levelLog = [];

  /// Brukerens egne bytter av øvelser (original -> ny).
  Map<String, String> exerciseSwaps = {};

  // Samsung-klokke via Health Connect
  bool watchSync = false;
  DateTime? lastWatchSync;
  Set<String> importedWorkoutIds = {};

  /// Det klokka registrerte (siste 90 dager), nyeste først.
  List<WatchData> watchLog = [];

  WatchData? watchDataById(String? id) => id == null ? null : watchLog.where((w) => w.id == id).firstOrNull;

  void putWatchData(WatchData d) {
    watchLog.removeWhere((w) => w.id == d.id);
    watchLog.add(d);
    watchLog.sort((a, b) => b.start.compareTo(a.start));
    final cut = clock().subtract(const Duration(days: 90));
    watchLog.removeWhere((w) => w.start.isBefore(cut));
    if (watchLog.length > 150) watchLog = watchLog.sublist(0, 150);
  }

  // Guidet økt
  bool voiceOn = true;
  MusicMode musicMode = MusicMode.appen;
  MusicGenre musicGenre = MusicGenre.pop;
  int extraRestSec = 0;

  /// Sist endret (brukes for å avgjøre om skyen eller telefonen er nyest).
  DateTime? modifiedAt;

  /// Kalles etter hver endring (synk til skyen).
  void Function()? onChanged;

  DateTime get today => dateOnly(clock());

  // ---------- Lagring ----------

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // Ødelagte data: start på nytt i stedet for å krasje.
      }
    }
    refreshMissed();
    loaded = true;
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(toJson()));
  }

  Map<String, dynamic> toJson() => {
        'profile': profile?.toJson(),
        'weeks': weeks.map((w) => w.toJson()).toList(),
        'measurements': measurements.map((m) => m.toJson()).toList(),
        'tests': tests.map((t) => t.toJson()).toList(),
        'lastSetback': lastSetback?.toIso8601String(),
        'holdWeek': holdWeek,
        'absences': absences.map((a) => a.toJson()).toList(),
        'levelLog': levelLog.map((l) => l.toJson()).toList(),
        'exerciseSwaps': exerciseSwaps,
        'watchSync': watchSync,
        'lastWatchSync': lastWatchSync?.toIso8601String(),
        'importedWorkoutIds': importedWorkoutIds.toList(),
        'watchLog': watchLog.map((w) => w.toJson()).toList(),
        'modifiedAt': modifiedAt?.toIso8601String(),
        'voiceOn': voiceOn,
        'musicMode': musicMode.name,
        'musicGenre': musicGenre.name,
        'extraRestSec': extraRestSec,
      };

  void fromJson(Map<String, dynamic> j) {
    profile = j['profile'] == null ? null : Profile.fromJson(j['profile']);
    weeks = ((j['weeks'] as List?) ?? []).map((w) => WeekPlan.fromJson(w)).toList();
    measurements = ((j['measurements'] as List?) ?? []).map((m) => Measurement.fromJson(m)).toList();
    tests = ((j['tests'] as List?) ?? []).map((t) => TestResult.fromJson(t)).toList();
    lastSetback = j['lastSetback'] == null ? null : DateTime.parse(j['lastSetback']);
    holdWeek = j['holdWeek'];
    absences = ((j['absences'] as List?) ?? []).map((a) => Absence.fromJson(a)).toList();
    levelLog = ((j['levelLog'] as List?) ?? []).map((l) => LevelChange.fromJson(l)).toList();
    exerciseSwaps = Map<String, String>.from(j['exerciseSwaps'] ?? {});
    watchSync = j['watchSync'] ?? false;
    lastWatchSync = j['lastWatchSync'] == null ? null : DateTime.parse(j['lastWatchSync']);
    importedWorkoutIds = ((j['importedWorkoutIds'] as List?) ?? []).cast<String>().toSet();
    watchLog = [for (final w in (j['watchLog'] as List?) ?? []) WatchData.fromJson(Map<String, dynamic>.from(w))];
    modifiedAt = j['modifiedAt'] == null ? null : DateTime.parse(j['modifiedAt']);
    voiceOn = j['voiceOn'] ?? true;
    musicMode = MusicMode.values.asNameMap()[j['musicMode']] ?? MusicMode.appen;
    musicGenre = MusicGenre.values.asNameMap()[j['musicGenre']] ?? MusicGenre.pop;
    extraRestSec = j['extraRestSec'] ?? 0;
  }

  void setCoachSettings({bool? voice, MusicMode? music, MusicGenre? genre, int? extraRest}) {
    if (voice != null) voiceOn = voice;
    if (music != null) musicMode = music;
    if (genre != null) musicGenre = genre;
    if (extraRest != null) extraRestSec = extraRest;
    _changed();
  }

  /// Bytt ut alt med data fra skyen (f.eks. ved ny telefon).
  Future<void> replaceWith(Map<String, dynamic> data) async {
    fromJson(data);
    refreshMissed();
    notifyListeners();
    await save();
  }

  // ---------- Klokke ----------

  void setWatchSync(bool on) {
    watchSync = on;
    _changed();
  }

  /// Legg inn økter og vekt hentet fra klokka.
  ImportResult importFromWatch(List<ImportedWorkout> workouts, {List<(DateTime, double)> weights = const []}) {
    refreshMissed();
    final r = applyWorkouts(this, workouts);
    r.weights = applyWeights(this, weights);
    lastWatchSync = clock();
    _changed();
    return r;
  }

  /// Slå sammen klokkeøkter (se watch_import.dart).
  ImportResult mergeWatch(List<String> ids) {
    final r = mergeWatchWorkouts(this, ids);
    refreshMissed();
    _changed();
    return r;
  }

  ImportResult splitWatch(String id) {
    final r = splitWatchWorkout(this, id);
    refreshMissed();
    _changed();
    return r;
  }

  void _changed() {
    modifiedAt = DateTime.now();
    notifyListeners();
    save();
    onChanged?.call();
  }

  void _log(int delta, String reason) {
    levelLog.add(LevelChange(date: today, delta: delta, reason: reason));
  }

  List<LevelChange> get unseenChanges => levelLog.where((l) => !l.seen).toList();

  void markChangesSeen() {
    for (final l in levelLog) {
      l.seen = true;
    }
    _changed();
  }

  // ---------- Plan ----------

  /// Ny plan fra bunnen av.
  void createPlan(Profile p) {
    profile = p;
    weeks = generatePlan(p);
    lastSetback = null;
    holdWeek = null;
    absences = [];
    levelLog = [];
    // Økter før planen ble laget, regnes ikke som tapt.
    for (final w in weeks) {
      for (final s in w.sessions) {
        if (s.date.isBefore(today)) {
          s.status = SessionStatus.staattOver;
          s.resolved = true;
          s.resolution = Resolution.forOppstart;
          s.note = 'Før oppstart';
        }
      }
    }
    if (!measurements.any((m) => m.weightKg != null && m.date == p.startDate)) {
      addMeasurementSilently(Measurement(date: p.startDate, weightKg: p.weightKg));
    }
    refreshMissed();
    _changed();
  }

  /// Planen har en startdato fram i tid.
  bool get notStarted => profile != null && today.isBefore(dateOnly(profile!.startDate));

  /// Flytt starten til i dag (bare før planen har startet). Sluttdato og mål beholdes.
  /// Klokkeøkter som ble holdt utenfor fordi de var før start, vurderes på nytt ved neste henting.
  void startToday() {
    final p = profile;
    if (p == null || !notStarted) return;
    final oldStart = dateOnly(p.startDate);
    measurements.removeWhere((m) => m.date == oldStart && m.weightKg == p.weightKg && m.waistCm == null);
    for (final w in watchLog.where((w) => !dateOnly(w.start).isBefore(today) && w.outcome.startsWith('Før planen'))) {
      importedWorkoutIds.remove(w.id);
      w.outcome = '';
    }
    createPlan(p.copyWith(startDate: today));
    _log(0, 'Planen er flyttet til å starte i dag, ${fmtDato(today)}.');
    _changed();
  }

  int get currentWeekIndex => weekFor(today)?.index ?? (today.isBefore(weeks.first.monday) ? -1 : weeks.length);

  /// Første uke som kan endres når målene justeres (uka etter denne).
  int get firstAdjustableWeek {
    if (weeks.isEmpty || today.isBefore(weeks.first.monday)) return 0;
    final cw = weekFor(today)?.index ?? weeks.length;
    return cw + 1;
  }

  /// Første mulige måldato ved justering: minst to uker frem.
  DateTime get earliestNewEndDate {
    if (weeks.isEmpty) return today.add(const Duration(days: 14));
    final from = firstAdjustableWeek;
    final monday = from < weeks.length ? weeks[from].monday : weeks.last.monday.add(const Duration(days: 7));
    return monday.add(const Duration(days: 13));
  }

  /// Siste mulige måldato (planen er maks [maxPlanWeeks] uker).
  DateTime latestEndDate(DateTime start) => start.add(const Duration(days: 7 * maxPlanWeeks - 1));

  /// Juster mål underveis. Gjennomførte og pågående uker beholdes,
  /// kommende uker bygges på nytt fra nivået du er på nå. Økes mengden,
  /// trappes den opp med maks 10 % per uke. Returnerer uka (1-basert) der
  /// alle økter er med (null hvis det ikke skjer innen planen er slutt).
  ({bool ramped, int? fullWeek}) adjustPlan(Profile p, {double? currentWeightKg}) {
    final old = profile;
    final from = firstAdjustableWeek;
    if (old == null || weeks.isEmpty || from == 0) {
      // Planen har ikke startet ennå: bare lag den på nytt.
      createPlan(p);
      if (currentWeightKg != null) addMeasurement(Measurement(date: today, weightKg: currentWeightKg));
      return (ramped: false, fullWeek: null);
    }
    // Startdato og startvekt ligger fast.
    final np = Profile(
      age: p.age,
      heightCm: p.heightCm,
      weightKg: old.weightKg,
      targetKg: p.targetKg,
      startDate: old.startDate,
      endDate: p.endDate,
      fitness: p.fitness,
      intensity: p.intensity,
      daysPerWeek: p.daysPerWeek,
      minutesPerSession: p.minutesPerSession,
      activities: p.activities,
      healthWarning: p.healthWarning,
      trainingDays: p.trainingDays,
      maxHr: p.maxHr,
      hrUnreliable: p.hrUnreliable,
      goal: p.goal,
    );
    final keep = weeks.sublist(0, min(from, weeks.length));
    final last = keep.last;
    // Hold nivået jevnt selv om planen blir lengre eller kortere.
    final scale = progressionSpan(np.totalWeeks) / progressionSpan(old.totalWeeks);
    var counter = ((last.progression + 1) * scale).round();
    final rebuilt = <WeekPlan>[...keep];
    var lowered = false;
    for (var i = keep.length; i < np.totalWeeks; i++) {
      final monday = keep.first.monday.add(Duration(days: 7 * i));
      if (monday.isAfter(np.endDate)) break;
      final deload = isDeloadWeek(i, np.totalWeeks);
      final w = WeekPlan(
        index: i,
        monday: monday,
        progression: deload ? max(0, counter - 1) : counter,
        deload: deload,
        phase: phaseFor(i, np.totalWeeks),
        sessions: [],
      );
      w.sessions = sessionsForWeek(np, w);
      rebuilt.add(w);
      // Mer trening enn før: start på et lavere nivå heller enn å øke mer enn 10 %.
      final limit = loadLimit(rebuilt, w, startDate: np.startDate);
      if (limit != null) {
        while (w.plannedLoad > limit && w.progression > 0) {
          w.progression -= 1;
          w.sessions = sessionsForWeek(np, w);
          lowered = true;
        }
        counter = deload ? w.progression + 1 : w.progression;
        // Fortsatt for mye på laveste nivå: kort ned / færre økter denne uka.
        enforceLoadCap(rebuilt, fromIndex: i, startDate: np.startDate);
      }
      if (!deload) counter++;
    }
    profile = np;
    weeks = rebuilt;
    // Fravær som går inn i kommende uker, gjelder fortsatt.
    _applyAbsenceMarks();
    if (currentWeightKg != null) {
      addMeasurementSilently(Measurement(date: today, weightKg: currentWeightKg));
    }
    // Opptrapping: når er alle valgte dager med?
    int expected(WeekPlan w) => sessionsForWeek(np, w).length;
    final fewer = from < weeks.length && weeks[from].plannedCount < expected(weeks[from]);
    final ramped = fewer || lowered;
    int? fullWeek;
    if (ramped) {
      fullWeek = weeks.skip(from).where((w) => !w.deload && w.plannedCount >= expected(w)).firstOrNull?.index;
      if (fullWeek != null) fullWeek += 1;
      final days = fewer
          ? (fullWeek != null
              ? ' Alle ${np.daysPerWeek} treningsdager er med fra uke $fullWeek.'
              : ' Ikke alle treningsdagene rekker å komme med før måldatoen.')
          : '';
      _log(0, 'Planen er justert. For å holde økningen innenfor 10 % per uke starter de nye ukene '
          'på et litt lavere nivå og bygger seg opp igjen.$days');
    }
    refreshMissed();
    _changed();
    return (ramped: ramped, fullWeek: fullWeek);
  }

  /// Start helt på nytt. Vekthistorikk og tester kan beholdes.
  void reset({bool keepHistory = false}) {
    profile = null;
    weeks = [];
    if (!keepHistory) {
      measurements = [];
      tests = [];
    }
    lastSetback = null;
    holdWeek = null;
    absences = [];
    levelLog = [];
    importedWorkoutIds = {};
    lastWatchSync = null;
    _changed();
  }

  WeekPlan? weekFor(DateTime d) => weekOf(weeks, d);

  WeekPlan? get currentWeek {
    if (weeks.isEmpty) return null;
    if (today.isBefore(weeks.first.monday)) return weeks.first;
    return weekFor(today) ?? weeks.last;
  }

  Session? get todaysOrNext {
    for (final w in weeks) {
      for (final s in w.sessions) {
        if (!s.date.isBefore(today) && s.status == SessionStatus.planlagt) return s;
      }
    }
    return null;
  }

  Iterable<Session> get _all sync* {
    for (final w in weeks) {
      yield* w.sessions;
    }
  }

  /// Økter fra tidligere dager som ikke er krysset av, regnes som stått over.
  /// Tapte økter eldre enn 14 dager lukkes. Ved tre tapte økter på to uker
  /// settes planen ett steg ned – før brukeren får forslag, så forslagene bygger på den nye planen.
  void refreshMissed() {
    for (final s in _all) {
      if (s.date.isBefore(today) && s.status == SessionStatus.planlagt && !s.extra) {
        s.status = SessionStatus.staattOver;
      }
      if (s.status == SessionStatus.staattOver && !s.resolved && !s.extra && today.difference(s.date).inDays > 14) {
        s.resolved = true;
        s.resolution = Resolution.utlopt;
        s.note = 'Ikke tatt igjen';
      }
    }
    _applyAbsenceMarks();
    autoCover(weeks);
    if (weeks.isNotEmpty && profile != null) _checkSetback();
  }

  /// Økter i registrert fravær som ikke er gjort, merkes som pause.
  void _applyAbsenceMarks() {
    for (final a in absences) {
      for (final s in _all) {
        if (s.extra || !a.contains(s.date) || s.status == SessionStatus.fullfort) continue;
        if (s.status == SessionStatus.staattOver && s.resolution != null && s.resolution != Resolution.utlopt) continue;
        s.status = SessionStatus.staattOver;
        s.resolved = true;
        s.resolution = Resolution.pause;
        s.note = 'Pause (${a.reason.toLowerCase()})';
      }
    }
  }

  List<Session> get unresolvedMissed =>
      [for (final s in _all) if (s.status == SessionStatus.staattOver && !s.resolved && !s.extra) s];

  /// Dato for siste gjennomførte økt (planlagt eller ekstra).
  DateTime? get lastActivity {
    DateTime? d;
    for (final s in _all) {
      if (s.status == SessionStatus.fullfort && (d == null || s.date.isAfter(d))) d = s.date;
    }
    return d;
  }

  /// Ser det ut som brukeren har vært borte (minst 7 dager uten trening og flere tapte økter)?
  /// Gir perioden som foreslås registrert som fravær.
  ({DateTime from, DateTime to})? get suggestedAbsence {
    if (profile == null || weeks.isEmpty) return null;
    final last = lastActivity ?? profile!.startDate.subtract(const Duration(days: 1));
    final from = last.add(const Duration(days: 1));
    final to = today.subtract(const Duration(days: 1));
    if (today.difference(last).inDays < 8 || to.difference(from).inDays < 6) return null;
    // Minst tre tapte økter siden sist (også de som er for gamle til å tas igjen).
    final missed = _all.where((s) =>
        !s.extra &&
        !s.date.isBefore(from) &&
        s.status == SessionStatus.staattOver &&
        (!s.resolved || s.resolution == Resolution.utlopt));
    if (missed.length < 3) return null;
    return (from: from, to: to);
  }

  bool get _holdUsedThisWeek => holdWeek != null && holdWeek == currentWeekIndex;

  /// Tre stått-over-økter på to uker: progresjonen går ett steg ned (maks én gang per uke).
  /// Ikke ved lengre fravær – da håndteres det samlet når fraværet registreres.
  void _checkSetback() {
    if (lastSetback != null && today.difference(lastSetback!).inDays < 14) return;
    if (_holdUsedThisWeek || suggestedAbsence != null) return;
    final missed = [for (final s in _all) if (s.countsAsMissed && today.difference(s.date).inDays <= 14) s];
    final from = firstFutureWeekIndex(weeks, today);
    if (missed.length >= 3 && from < weeks.length) {
      regenerateFrom(profile!, weeks, from, progressionDelta: -1);
      lastSetback = today;
      holdWeek = currentWeekIndex;
      _log(-1, 'Du har stått over ${missed.length} økter de siste to ukene, så de neste ukene er gjort litt lettere.');
    }
  }

  // ---------- Fravær ----------

  /// Registrer fravær (sykdom, ferie, skade). Økter i perioden teller ikke som tapt.
  /// Etter fravær på minst en uke starter planen med en lettere uke og et lavere nivå.
  /// [shiftEndDate] flytter måldatoen like mange uker frem.
  void registerAbsence(DateTime from, DateTime to, String reason, {bool shiftEndDate = false}) {
    final p = profile!;
    final a = Absence(from: from, to: to, reason: reason);
    if (shiftEndDate) {
      final shift = (a.days / 7).ceil();
      final newEnd = p.endDate.add(Duration(days: 7 * shift));
      final capped = newEnd.isAfter(latestEndDate(p.startDate)) ? latestEndDate(p.startDate) : newEnd;
      adjustPlan(p.copyWith(endDate: capped));
    }
    absences.add(a);
    _applyAbsenceMarks();
    // Nivåsteg, minus tilbakesteg som allerede er gjort i perioden.
    final steps = absenceSteps(a.days);
    final alreadyDown = levelLog
        .where((l) => !l.date.isBefore(a.from) && l.delta < 0)
        .fold<int>(0, (s, l) => s - l.delta);
    final back = a.to.add(const Duration(days: 1));
    final rw = weekFor(back) ?? (back.isBefore(weeks.first.monday) ? weeks.first : null);
    if (rw != null && steps > 0) {
      final delta = steps == 99 ? -rw.progression : -max(0, steps - alreadyDown);
      // Første uke tilbake er lettere.
      rw.deload = true;
      regenerateFrom(profile!, weeks, rw.index, progressionDelta: delta);
      a.appliedSteps = -delta;
      holdWeek = currentWeekIndex;
      _log(delta,
          'Fravær i ${a.days} dager (${reason.toLowerCase()}). Uke ${rw.index + 1} er en lettere uke, og planen er satt ${steps == 99 ? 'tilbake til start' : '${-delta} steg ned'} før den bygger seg opp igjen.');
    } else {
      _log(0, 'Fravær ${fmtDato(a.from)}–${fmtDato(a.to)} (${reason.toLowerCase()}) er registrert.');
    }
    _changed();
  }

  /// Fravær som pågår eller kommer.
  Absence? get activeAbsence =>
      absences.where((a) => !a.to.isBefore(today) && !a.from.isAfter(today.add(const Duration(days: 14)))).firstOrNull;

  /// Avslutt fravær tidligere enn planlagt (f.eks. frisk før ventet).
  void endAbsenceNow(Absence a) {
    if (a.to.isBefore(today)) return;
    final newTo = today.subtract(const Duration(days: 1));
    if (newTo.isBefore(a.from)) {
      absences.remove(a);
    } else {
      a.to = newTo;
    }
    // Gi tilbake økter fra i dag.
    for (final s in _all) {
      if (s.resolution == Resolution.pause && !s.date.isBefore(today) && !absences.any((x) => x.contains(s.date))) {
        s.status = SessionStatus.planlagt;
        s.resolved = false;
        s.resolution = null;
        s.note = null;
      }
    }
    final newSteps = absences.contains(a) ? absenceSteps(a.days) : 0;
    final up = a.appliedSteps - (newSteps == 99 ? a.appliedSteps : newSteps);
    final cw = max(0, currentWeekIndex);
    if (cw < weeks.length) regenerateFrom(profile!, weeks, cw, progressionDelta: up > 0 ? up : 0);
    if (absences.contains(a)) a.appliedSteps -= max(0, up);
    _log(up, 'Fraværet er avsluttet. Planen fortsetter fra i dag.');
    _changed();
  }

  // ---------- Økter ----------

  void markDone(Session s, {Feeling? feeling}) {
    s.status = SessionStatus.fullfort;
    s.resolved = true;
    s.feeling = feeling;
    if (feeling != null) _adjustByFeeling();
    _changed();
  }

  void markNotDone(Session s) {
    if (s.extra) {
      deleteExtra(s);
      return;
    }
    s.status = s.date.isBefore(today) ? SessionStatus.staattOver : SessionStatus.planlagt;
    s.resolved = false;
    s.resolution = null;
    s.note = null;
    refreshMissed();
    _changed();
  }

  /// Rett en registrering: faktisk varighet, anstrengelse, følelse – og for ekstraøkter også type.
  void editSession(Session s, {int? minutes, Effort? effort, Feeling? feeling, bool clearFeeling = false, SessionType? type, String? title}) {
    if (minutes != null) s.minutes = minutes.clamp(5, 300);
    if (effort != null) s.effort = effort;
    if (clearFeeling) s.feeling = null;
    if (feeling != null) s.feeling = feeling;
    if (s.extra) {
      if (type != null) s.type = type;
      if (title != null) s.title = title;
      // Sjekk om ekstraøkta fortsatt kan ta igjen den tapte økta.
      if (s.covers != null) {
        final m = _all.where((x) => x.id == s.covers).firstOrNull;
        if (m != null && !canCover(s, m, weeks)) {
          m.resolved = false;
          m.resolution = null;
          m.note = null;
          s.covers = null;
          s.note = null;
        }
      }
      autoCover(weeks);
    }
    _changed();
  }

  /// Etterregistrering: økta ble gjort på sin egen dato, men ikke krysset av.
  /// Trente du en annen dag, skal det registreres som ekstra økt i stedet.
  void backRegister(Session s, {Feeling? feeling}) {
    assert(s.canBackRegister);
    if (s.resolution == Resolution.strokket && s.compRefs.contains('hold')) {
      // Planen ble holdt igjen for denne økta – gi tilbake nivået.
      undoCompensation(weeks, profile!, s, today);
    }
    s.status = SessionStatus.fullfort;
    s.resolved = true;
    s.resolution = null;
    s.feeling = feeling;
    s.note = 'Etterregistrert';
    _changed();
  }

  /// Økter i planen samme dag og av samme type som ikke er krysset av.
  Session? plannedMatch(DateTime date, SessionType type) {
    for (final s in weekFor(date)?.sessions ?? const <Session>[]) {
      if (!s.extra &&
          s.date == dateOnly(date) &&
          s.category == categoryOf(type) &&
          s.status != SessionStatus.fullfort &&
          (s.resolution == null || s.resolution == Resolution.forOppstart)) {
        return s;
      }
    }
    return null;
  }

  /// Registrer økt utenom planen (i dag eller tilbake i tid).
  /// Returnerer tapte økter som ble dekket av den.
  List<Session> addExtra({
    required DateTime date,
    required SessionType type,
    required String title,
    required int minutes,
    required Effort effort,
  }) {
    final d = dateOnly(date);
    final w = weekFor(d);
    if (w == null || d.isAfter(today)) {
      throw ArgumentError('Datoen må være innenfor planen og ikke i fremtiden');
    }
    final s = Session(
      id: 'ekstra-${DateTime.now().microsecondsSinceEpoch}',
      date: d,
      type: type,
      title: title,
      minutes: minutes,
      effort: effort,
      status: SessionStatus.fullfort,
      resolved: true,
      extra: true,
    );
    w.sessions.add(s);
    w.sessions.sort((a, b) => a.date.compareTo(b.date));
    final covered = autoCover(weeks);
    _changed();
    return covered;
  }

  void deleteExtra(Session e) {
    for (final w in weeks) {
      w.sessions.remove(e);
    }
    if (e.covers != null) {
      for (final s in _all) {
        if (s.id == e.covers && s.resolution == Resolution.ekstraOkt) {
          s.resolved = false;
          s.resolution = null;
          s.note = null;
        }
      }
    }
    refreshMissed();
    _changed();
  }

  List<CompensationOption> optionsFor(Session missed) => compensationOptions(
      weeks: weeks, profile: profile!, missed: missed, today: today, holdUsedThisWeek: _holdUsedThisWeek);

  void applyCompensation(CompensationOption o, Session missed) {
    o.apply(weeks, profile!, missed);
    if (missed.compRefs.contains('hold')) holdWeek = currentWeekIndex;
    _changed();
  }

  /// Angre en valgt løsning (flytt, fordel, stryk). Returnerer feilmelding eller null.
  String? undoCompensationFor(Session missed) {
    final hadHold = missed.compRefs.contains('hold');
    final err = undoCompensation(weeks, profile!, missed, today);
    if (err != null) return err;
    if (hadHold && holdWeek == currentWeekIndex) holdWeek = null;
    _changed();
    return null;
  }

  // ---------- Flytte, gjøre lettere, bytte øvelse ----------

  List<MoveOption> moveOptionsFor(Session s) => moveOptions(weeks, s, today, profile!.endDate);

  bool moveSession(Session s, MoveOption o) {
    final ok = applyMove(weeks, s, o);
    if (ok) _changed();
    return ok;
  }

  /// «Gjør lettere i dag» – bare for økter som ikke er gjort.
  void easeSession(Session s, Ease e) {
    if (s.status != SessionStatus.planlagt) return;
    applyEase(s, e);
    _changed();
  }

  void setExerciseSwap(String original, String? replacement) {
    if (replacement == null || replacement == original) {
      exerciseSwaps.remove(original);
    } else {
      exerciseSwaps[original] = replacement;
    }
    _changed();
  }

  void logExercises(Session s, Map<String, ExLog> log) {
    s.exLog = {...log}..removeWhere((k, v) => v.kg == null && v.reps == null);
    _changed();
  }

  /// Siste registrerte vekt/repetisjoner for en øvelse (forslag neste gang).
  ExLog? lastLogFor(String exId) {
    final done = _all.where((s) => s.exLog.containsKey(exId)).toList()..sort((a, b) => a.date.compareTo(b.date));
    return done.isEmpty ? null : done.last.exLog[exId];
  }

  /// Vekt over tid for en øvelse.
  List<(DateTime, double)> strengthHistory(String exId) => [
        for (final s in _all.toList()..sort((a, b) => a.date.compareTo(b.date)))
          if (s.exLog[exId]?.kg != null) (s.date, s.exLog[exId]!.kg!)
      ];

  Set<String> get loggedExercises => {for (final s in _all) ...s.exLog.keys};

  // ---------- Følelse ----------

  /// To økter på rad som «for tung» senker nivået, to «for lett» øker det.
  void _adjustByFeeling() {
    final rated = [for (final s in _all) if (s.feeling != null) s]..sort((a, b) => a.date.compareTo(b.date));
    if (rated.length < 2) return;
    final a = rated[rated.length - 1].feeling, b = rated[rated.length - 2].feeling;
    if (a != b || a == Feeling.passe) return;
    final from = firstFutureWeekIndex(weeks, today);
    if (from >= weeks.length) return;
    final down = a == Feeling.forTungt;
    regenerateFrom(profile!, weeks, from, progressionDelta: down ? -1 : 1);
    _log(down ? -1 : 1,
        down
            ? 'To økter på rad føltes for tunge, så de neste ukene er gjort litt lettere.'
            : 'To økter på rad føltes for lette, så de neste ukene er gjort litt tyngre (fortsatt maks 10 % økning per uke).');
    // Nullstill så samme par ikke teller to ganger.
    rated[rated.length - 1].feeling = Feeling.passe;
  }

  // ---------- Målinger ----------

  void addMeasurementSilently(Measurement m) {
    measurements.removeWhere((x) => x.date == m.date);
    measurements.add(m);
    measurements.sort((a, b) => a.date.compareTo(b.date));
  }

  /// Legg til eller erstatt måling. Kaster ArgumentError ved urealistiske verdier.
  void addMeasurement(Measurement m) {
    final err = validateWeight(m.weightKg) ?? validateWaist(m.waistCm);
    if (err != null) throw ArgumentError(err);
    if (m.date.isAfter(today)) throw ArgumentError('Datoen kan ikke være i fremtiden');
    addMeasurementSilently(m);
    _changed();
  }

  void updateMeasurement(Measurement old, Measurement updated) {
    final err = validateWeight(updated.weightKg) ?? validateWaist(updated.waistCm);
    if (err != null) throw ArgumentError(err);
    measurements.remove(old);
    addMeasurementSilently(updated);
    _changed();
  }

  void deleteMeasurement(Measurement m) {
    measurements.remove(m);
    _changed();
  }

  double? get latestWeight => measurements.where((m) => m.weightKg != null).lastOrNull?.weightKg;

  void addTest(TestResult t) {
    tests.removeWhere((x) => x.date == t.date);
    tests.add(t);
    tests.sort((a, b) => a.date.compareTo(b.date));
    _changed();
  }

  void deleteTest(TestResult t) {
    tests.remove(t);
    _changed();
  }

  /// Planlagt vekt på en gitt dato (lineært fra start til mål, flat ved «holde vekten»).
  double plannedWeight(DateTime d) {
    final p = profile!;
    if (p.holdsWeight) return p.weightKg;
    final total = p.endDate.difference(p.startDate).inDays;
    final gone = d.difference(p.startDate).inDays.clamp(0, total);
    return p.weightKg - (p.weightKg - p.targetKg) * gone / (total == 0 ? 1 : total);
  }

  /// Planlagte økter som er gjennomført eller tatt igjen.
  int get sessionsDone => _all
      .where((s) => !s.extra && (s.status == SessionStatus.fullfort || s.resolution == Resolution.ekstraOkt))
      .length;

  /// Planlagte økter fram til i dag (uten dem før oppstart og i fravær).
  int get sessionsSoFar => _all
      .where((s) =>
          !s.extra &&
          s.resolution != Resolution.forOppstart &&
          s.resolution != Resolution.pause &&
          (s.date.isBefore(today) || s.status == SessionStatus.fullfort))
      .length;

  int get extrasDone => _all.where((s) => s.extra).length;
}
