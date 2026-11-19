// App-tilstand med lagring på telefonen (fungerer uten nett).

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'compensation.dart';
import 'models.dart';
import 'plan_generator.dart';
import 'watch_import.dart';

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

  // Samsung-klokke via Health Connect
  bool watchSync = false;
  DateTime? lastWatchSync;
  Set<String> importedWorkoutIds = {};

  // Guidet økt
  bool voiceOn = true;
  MusicMode musicMode = MusicMode.appen;

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
        'watchSync': watchSync,
        'lastWatchSync': lastWatchSync?.toIso8601String(),
        'importedWorkoutIds': importedWorkoutIds.toList(),
        'modifiedAt': modifiedAt?.toIso8601String(),
        'voiceOn': voiceOn,
        'musicMode': musicMode.name,
      };

  void fromJson(Map<String, dynamic> j) {
    profile = j['profile'] == null ? null : Profile.fromJson(j['profile']);
    weeks = ((j['weeks'] as List?) ?? []).map((w) => WeekPlan.fromJson(w)).toList();
    measurements = ((j['measurements'] as List?) ?? []).map((m) => Measurement.fromJson(m)).toList();
    tests = ((j['tests'] as List?) ?? []).map((t) => TestResult.fromJson(t)).toList();
    lastSetback = j['lastSetback'] == null ? null : DateTime.parse(j['lastSetback']);
    watchSync = j['watchSync'] ?? false;
    lastWatchSync = j['lastWatchSync'] == null ? null : DateTime.parse(j['lastWatchSync']);
    importedWorkoutIds = ((j['importedWorkoutIds'] as List?) ?? []).cast<String>().toSet();
    modifiedAt = j['modifiedAt'] == null ? null : DateTime.parse(j['modifiedAt']);
    voiceOn = j['voiceOn'] ?? true;
    musicMode = MusicMode.values.asNameMap()[j['musicMode']] ?? MusicMode.appen;
  }

  void setCoachSettings({bool? voice, MusicMode? music}) {
    if (voice != null) voiceOn = voice;
    if (music != null) musicMode = music;
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

  void _changed() {
    modifiedAt = DateTime.now();
    notifyListeners();
    save();
    onChanged?.call();
  }

  // ---------- Plan ----------

  /// Ny plan fra bunnen av.
  void createPlan(Profile p) {
    profile = p;
    weeks = generatePlan(p);
    lastSetback = null;
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

  /// Første uke som kan endres når målene justeres (uka etter denne).
  int get firstAdjustableWeek {
    if (weeks.isEmpty || today.isBefore(weeks.first.monday)) return 0;
    final cw = weekFor(today)?.index ?? weeks.length;
    return cw + 1;
  }

  /// Siste mulige måldato-uke ved justering: minst to uker frem.
  DateTime get earliestNewEndDate {
    if (weeks.isEmpty) return today.add(const Duration(days: 14));
    final from = firstAdjustableWeek;
    final monday = from < weeks.length
        ? weeks[from].monday
        : weeks.last.monday.add(const Duration(days: 7));
    return monday.add(const Duration(days: 13));
  }

  /// Juster mål underveis. Gjennomførte og pågående uker beholdes,
  /// kommende uker bygges på nytt med samme nivå som du er på nå.
  void adjustPlan(Profile p, {double? currentWeightKg}) {
    final old = profile;
    final from = firstAdjustableWeek;
    if (old == null || weeks.isEmpty || from == 0) {
      // Planen har ikke startet ennå: bare lag den på nytt.
      createPlan(p);
      if (currentWeightKg != null) addMeasurement(Measurement(date: today, weightKg: currentWeightKg));
      return;
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
    );
    final keep = weeks.sublist(0, min(from, weeks.length));
    final last = keep.last;
    // Hold nivået jevnt selv om planen blir lengre eller kortere.
    final scale = progressionSpan(np.totalWeeks) / progressionSpan(old.totalWeeks);
    var counter = ((last.progression + 1) * scale).round();
    final rebuilt = <WeekPlan>[...keep];
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
      if (!deload) counter++;
    }
    profile = np;
    weeks = rebuilt;
    enforceLoadCap(weeks);
    if (currentWeightKg != null) {
      addMeasurementSilently(Measurement(date: today, weightKg: currentWeightKg));
    }
    refreshMissed();
    _changed();
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

  /// Økter fra tidligere dager som ikke er krysset av, regnes som stått over.
  void refreshMissed() {
    for (final w in weeks) {
      for (final s in w.sessions) {
        if (s.date.isBefore(today) && s.status == SessionStatus.planlagt && !s.extra) {
          s.status = SessionStatus.staattOver;
        }
      }
    }
    autoCover(weeks);
  }

  List<Session> get unresolvedMissed => [
        for (final w in weeks)
          for (final s in w.sessions)
            if (s.status == SessionStatus.staattOver &&
                !s.resolved &&
                !s.extra &&
                today.difference(s.date).inDays <= 14)
              s
      ];

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

  /// Etterregistrering: økta ble gjort på sin egen dato, men ikke krysset av.
  /// Trente du en annen dag, skal det registreres som ekstra økt i stedet.
  void backRegister(Session s, {Feeling? feeling}) {
    assert(s.canBackRegister);
    if (s.resolution == Resolution.strokket) {
      // Planen ble holdt igjen for denne økta – gi tilbake nivået.
      final from = firstAdjustableWeek;
      if (from < weeks.length) regenerateFrom(profile!, weeks, from, progressionDelta: 1);
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
      for (final w in weeks) {
        for (final s in w.sessions) {
          if (s.id == e.covers && s.resolution == Resolution.ekstraOkt) {
            s.resolved = false;
            s.resolution = null;
            s.note = null;
          }
        }
      }
    }
    refreshMissed();
    _changed();
  }

  List<CompensationOption> optionsFor(Session missed) =>
      compensationOptions(weeks: weeks, profile: profile!, missed: missed, today: today);

  void applyCompensation(CompensationOption o, Session missed) {
    o.apply(weeks, profile!, missed);
    _checkSetback();
    _changed();
  }

  int get _firstFutureWeek =>
      weeks.where((w) => w.monday.isAfter(today)).firstOrNull?.index ?? weeks.length;

  /// Tre stått-over-økter på to uker: progresjonen går én uke tilbake.
  void _checkSetback() {
    if (lastSetback != null && today.difference(lastSetback!).inDays < 14) return;
    final missed = [
      for (final w in weeks)
        for (final s in w.sessions)
          if (s.countsAsMissed && today.difference(s.date).inDays <= 14) s
    ];
    if (missed.length >= 3 && _firstFutureWeek < weeks.length) {
      regenerateFrom(profile!, weeks, _firstFutureWeek, progressionDelta: -1);
      lastSetback = today;
    }
  }

  /// To økter på rad som «for tung» senker nivået, to «for lett» øker det.
  void _adjustByFeeling() {
    final rated = [
      for (final w in weeks)
        for (final s in w.sessions)
          if (s.feeling != null) s
    ]..sort((a, b) => a.date.compareTo(b.date));
    if (rated.length < 2) return;
    final a = rated[rated.length - 1].feeling, b = rated[rated.length - 2].feeling;
    if (a != b || a == Feeling.passe) return;
    if (_firstFutureWeek >= weeks.length) return;
    regenerateFrom(profile!, weeks, _firstFutureWeek, progressionDelta: a == Feeling.forTungt ? -1 : 1);
    // Nullstill så samme par ikke teller to ganger.
    rated[rated.length - 1].feeling = Feeling.passe;
  }

  // ---------- Målinger ----------

  void addMeasurementSilently(Measurement m) {
    measurements.removeWhere((x) => x.date == m.date);
    measurements.add(m);
    measurements.sort((a, b) => a.date.compareTo(b.date));
  }

  void addMeasurement(Measurement m) {
    addMeasurementSilently(m);
    _changed();
  }

  double? get latestWeight => measurements.where((m) => m.weightKg != null).lastOrNull?.weightKg;

  void addTest(TestResult t) {
    tests.removeWhere((x) => x.date == t.date);
    tests.add(t);
    tests.sort((a, b) => a.date.compareTo(b.date));
    _changed();
  }

  /// Planlagt vekt på en gitt dato (lineært fra start til mål).
  double plannedWeight(DateTime d) {
    final p = profile!;
    final total = p.endDate.difference(p.startDate).inDays;
    final gone = d.difference(p.startDate).inDays.clamp(0, total);
    return p.weightKg - (p.weightKg - p.targetKg) * gone / (total == 0 ? 1 : total);
  }

  Iterable<Session> get _all sync* {
    for (final w in weeks) {
      yield* w.sessions;
    }
  }

  /// Planlagte økter som er gjennomført eller tatt igjen.
  int get sessionsDone => _all
      .where((s) => !s.extra && (s.status == SessionStatus.fullfort || s.resolution == Resolution.ekstraOkt))
      .length;

  /// Planlagte økter fram til i dag (uten dem før oppstart).
  int get sessionsSoFar => _all
      .where((s) =>
          !s.extra &&
          s.resolution != Resolution.forOppstart &&
          (s.date.isBefore(today) || s.status == SessionStatus.fullfort))
      .length;

  int get extrasDone => _all.where((s) => s.extra).length;
}
