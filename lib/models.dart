// Datamodeller for treningsplanen.

enum Intensity { rolig, moderat, krevende }

enum Fitness { liteAktiv, gaarRaskt, kanJogge, trenerJevnlig }

enum Activity { manualer, raskGange, motbakker, jogging, benk }

/// Mål for planen: gå ned i vekt, eller holde vekten / bedre form.
enum GoalType { vektned, holde }

/// Lengste plan appen lager (uker).
const maxPlanWeeks = 104;

enum SessionType { motbakke, styrkeA, styrkeB, langtur, kondisjon, restitusjon }

enum Effort { lett, moderat, hard }

enum SessionStatus { planlagt, fullfort, staattOver }

enum Feeling { forLett, passe, forTungt }

/// Musikk under guidet økt: ingen, appens egne låter, eller brukerens egen (Spotify o.l.).
enum MusicMode { av, appen, egen }

/// Musikktype for appens egne låter.
enum MusicGenre {
  rolig('Rolig'),
  piano('Piano'),
  rock('Rock'),
  pop('Pop'),
  klassisk('Klassisk');

  final String label;
  const MusicGenre(this.label);

  String get workAsset => 'assets/musikk/${name}_arbeid.mp3';
  String get restAsset => 'assets/musikk/${name}_pause.mp3';
}

/// Hvordan en stått-over-økt ble håndtert.
enum Resolution { forOppstart, flyttet, fordelt, strokket, ekstraOkt, pause, utlopt }

/// Hvordan en økt er gjort lettere for dagen.
enum Ease { kortere, rolig }

/// Kondisjon og styrke kan ikke erstatte hverandre.
enum Category { kondisjon, styrke }

Category categoryOf(SessionType t) =>
    t == SessionType.styrkeA || t == SessionType.styrkeB ? Category.styrke : Category.kondisjon;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class Profile {
  final int age;
  final int heightCm;
  final double weightKg;
  final double targetKg;
  final DateTime startDate;
  final DateTime endDate;
  final Fitness fitness;
  final Intensity intensity;
  final int daysPerWeek; // 3–6
  final int minutesPerSession; // 30, 45 eller 60
  final Set<Activity> activities;
  final bool healthWarning;

  /// Valgte treningsdager (0 = mandag). Null = standard for antall dager.
  final List<int>? trainingDays;

  /// Egen makspuls, hvis kjent.
  final int? maxHr;

  /// Bruker medisin som påvirker pulsen (f.eks. betablokker) – pulsen brukes ikke.
  final bool hrUnreliable;
  final GoalType goal;

  Profile({
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.targetKg,
    required DateTime startDate,
    required DateTime endDate,
    required this.fitness,
    required this.intensity,
    required this.daysPerWeek,
    required this.minutesPerSession,
    required this.activities,
    this.healthWarning = false,
    this.trainingDays,
    this.maxHr,
    this.hrUnreliable = false,
    this.goal = GoalType.vektned,
  })  : startDate = dateOnly(startDate),
        endDate = dateOnly(endDate);

  int get totalWeeks {
    final days = endDate.difference(startDate).inDays;
    return ((days + 1) / 7).ceil().clamp(1, maxPlanWeeks);
  }

  /// Mål om å holde vekten (eller ingen nedgang ønsket).
  bool get holdsWeight => goal == GoalType.holde || targetKg >= weightKg;

  double get kgPerWeek => holdsWeight ? 0 : (weightKg - targetKg) / totalWeeks;

  bool has(Activity a) => activities.contains(a);

  Profile copyWith({
    double? weightKg,
    double? targetKg,
    DateTime? startDate,
    DateTime? endDate,
    int? daysPerWeek,
    List<int>? trainingDays,
  }) =>
      Profile(
        age: age,
        heightCm: heightCm,
        weightKg: weightKg ?? this.weightKg,
        targetKg: targetKg ?? this.targetKg,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        fitness: fitness,
        intensity: intensity,
        daysPerWeek: daysPerWeek ?? this.daysPerWeek,
        minutesPerSession: minutesPerSession,
        activities: activities,
        healthWarning: healthWarning,
        trainingDays: trainingDays ?? this.trainingDays,
        maxHr: maxHr,
        hrUnreliable: hrUnreliable,
        goal: goal,
      );

  /// Omtrentlig daglig kaloriunderskudd (ca. 7700 kcal per kg).
  int get dailyDeficitKcal => (kgPerWeek * 7700 / 7).round();

  /// Mer enn ca. 1 % av kroppsvekten per uke regnes som for raskt.
  bool get goalTooAggressive => kgPerWeek > weightKg * 0.01;

  bool get isSenior => age >= 60;

  Map<String, dynamic> toJson() => {
        'age': age,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'targetKg': targetKg,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'fitness': fitness.name,
        'intensity': intensity.name,
        'daysPerWeek': daysPerWeek,
        'minutesPerSession': minutesPerSession,
        'activities': activities.map((a) => a.name).toList(),
        'healthWarning': healthWarning,
        'trainingDays': trainingDays,
        'maxHr': maxHr,
        'hrUnreliable': hrUnreliable,
        'goal': goal.name,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        age: j['age'],
        heightCm: j['heightCm'],
        weightKg: (j['weightKg'] as num).toDouble(),
        targetKg: (j['targetKg'] as num).toDouble(),
        startDate: DateTime.parse(j['startDate']),
        endDate: DateTime.parse(j['endDate']),
        fitness: Fitness.values.byName(j['fitness']),
        intensity: Intensity.values.byName(j['intensity']),
        daysPerWeek: j['daysPerWeek'],
        minutesPerSession: j['minutesPerSession'],
        activities: (j['activities'] as List)
            .map((a) => Activity.values.byName(a as String))
            .toSet(),
        healthWarning: j['healthWarning'] ?? false,
        trainingDays: (j['trainingDays'] as List?)?.cast<int>(),
        maxHr: j['maxHr'],
        hrUnreliable: j['hrUnreliable'] ?? false,
        goal: GoalType.values.asNameMap()[j['goal']] ?? GoalType.vektned,
      );
}

/// Vekt og repetisjoner for én øvelse i en økt.
class ExLog {
  final double? kg;
  final int? reps;
  const ExLog({this.kg, this.reps});

  Map<String, dynamic> toJson() => {'kg': kg, 'reps': reps};
  factory ExLog.fromJson(Map<String, dynamic> j) => ExLog(kg: (j['kg'] as num?)?.toDouble(), reps: j['reps']);

  String get label => [
        if (kg != null) '${fmtKg(kg!)} kg',
        if (reps != null) '$reps rep',
      ].join(' × ');
}

class Session {
  final String id;
  DateTime date;
  SessionType type;
  String title;
  int minutes;
  Effort effort;
  // Intervaller
  int reps;
  int workSec;
  int restSec;
  // Styrke
  int rounds;
  int circuit; // 0 = Styrke A, 1–3 = sirkler
  // Status
  SessionStatus status;
  bool resolved; // tapt økt er håndtert
  Resolution? resolution;
  bool extra; // registrert utenom planen
  String? covers; // id til tapt økt som denne ekstraøkta erstatter
  String? note;
  Feeling? feeling;

  /// Minutter lagt til for å ta igjen en tapt økt (overlever ny utregning av uka).
  int addedMin;

  /// Gjort lettere for dagen.
  Ease? ease;

  /// For en tapt økt: hva kompensasjonen endret («add:<id>:<min>», «new:<id>», «hold»), så den kan angres.
  List<String> compRefs;

  /// Vekt og repetisjoner per øvelse (styrke).
  Map<String, ExLog> exLog;

  /// Id til økta fra klokka som krysset av eller registrerte denne (se AppState.watchLog).
  String? watchId;

  Session({
    required this.id,
    required DateTime date,
    required this.type,
    required this.title,
    required this.minutes,
    required this.effort,
    this.reps = 0,
    this.workSec = 0,
    this.restSec = 0,
    this.rounds = 0,
    this.circuit = 0,
    this.status = SessionStatus.planlagt,
    this.resolved = false,
    this.resolution,
    this.extra = false,
    this.covers,
    this.note,
    this.feeling,
    this.addedMin = 0,
    this.ease,
    List<String>? compRefs,
    Map<String, ExLog>? exLog,
    this.watchId,
  })  : date = dateOnly(date),
        compRefs = compRefs ?? [],
        exLog = exLog ?? {};

  bool get isHard => effort == Effort.hard;

  Category get category => categoryOf(type);

  /// Tapt økt som teller med i regelen om tre tapte økter på to uker.
  bool get countsAsMissed =>
      !extra &&
      status == SessionStatus.staattOver &&
      resolution != Resolution.forOppstart &&
      resolution != Resolution.ekstraOkt &&
      resolution != Resolution.pause &&
      resolution != Resolution.utlopt;

  /// Kan registreres som gjennomført i ettertid (på sin egen dato).
  bool get canBackRegister =>
      !extra &&
      status == SessionStatus.staattOver &&
      (resolution == null ||
          resolution == Resolution.forOppstart ||
          resolution == Resolution.strokket ||
          resolution == Resolution.pause ||
          resolution == Resolution.utlopt);

  /// En valgt løsning for tapt økt som kan angres.
  bool get canUndoCompensation =>
      !extra &&
      status == SessionStatus.staattOver &&
      (resolution == Resolution.flyttet || resolution == Resolution.fordelt || resolution == Resolution.strokket);

  /// Treningsbelastning: minutter vektet etter anstrengelse.
  double get load =>
      minutes * (effort == Effort.hard ? 2.0 : effort == Effort.moderat ? 1.5 : 1.0);

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'type': type.name,
        'title': title,
        'minutes': minutes,
        'effort': effort.name,
        'reps': reps,
        'workSec': workSec,
        'restSec': restSec,
        'rounds': rounds,
        'circuit': circuit,
        'status': status.name,
        'resolved': resolved,
        'resolution': resolution?.name,
        'extra': extra,
        'covers': covers,
        'note': note,
        'feeling': feeling?.name,
        'addedMin': addedMin,
        'ease': ease?.name,
        'compRefs': compRefs,
        'exLog': exLog.map((k, v) => MapEntry(k, v.toJson())),
        if (watchId != null) 'watchId': watchId,
      };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        id: j['id'],
        date: DateTime.parse(j['date']),
        type: SessionType.values.byName(j['type']),
        title: j['title'],
        minutes: j['minutes'],
        effort: Effort.values.byName(j['effort']),
        reps: j['reps'] ?? 0,
        workSec: j['workSec'] ?? 0,
        restSec: j['restSec'] ?? 0,
        rounds: j['rounds'] ?? 0,
        circuit: j['circuit'] ?? 0,
        status: SessionStatus.values.byName(j['status']),
        resolved: j['resolved'] ?? false,
        resolution: j['resolution'] == null ? null : Resolution.values.byName(j['resolution']),
        extra: j['extra'] ?? false,
        covers: j['covers'],
        note: j['note'],
        feeling: j['feeling'] == null ? null : Feeling.values.byName(j['feeling']),
        addedMin: j['addedMin'] ?? 0,
        ease: Ease.values.asNameMap()[j['ease']],
        compRefs: (j['compRefs'] as List?)?.cast<String>(),
        exLog: (j['exLog'] as Map?)?.map((k, v) => MapEntry(k as String, ExLog.fromJson(Map<String, dynamic>.from(v)))),
        watchId: j['watchId'],
      );
}

class WeekPlan {
  final int index; // 0-basert
  final DateTime monday;
  int progression; // nivå i progresjonsstigen
  bool deload;
  final String phase;
  List<Session> sessions;

  WeekPlan({
    required this.index,
    required DateTime monday,
    required this.progression,
    required this.deload,
    required this.phase,
    required this.sessions,
  }) : monday = dateOnly(monday);

  DateTime get sunday => monday.add(const Duration(days: 6));

  double get load => sessions.fold(0.0, (s, e) => s + e.load);

  /// Belastning fra planlagte økter (uten ekstraøkter brukeren har registrert selv).
  double get plannedLoad => sessions.where((s) => !s.extra).fold(0.0, (s, e) => s + e.load);

  int get plannedCount => sessions.where((s) => !s.extra).length;

  bool contains(DateTime d) {
    final x = dateOnly(d);
    return !x.isBefore(monday) && !x.isAfter(sunday);
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'monday': monday.toIso8601String(),
        'progression': progression,
        'deload': deload,
        'phase': phase,
        'sessions': sessions.map((s) => s.toJson()).toList(),
      };

  factory WeekPlan.fromJson(Map<String, dynamic> j) => WeekPlan(
        index: j['index'],
        monday: DateTime.parse(j['monday']),
        progression: j['progression'],
        deload: j['deload'],
        phase: j['phase'],
        sessions: (j['sessions'] as List).map((s) => Session.fromJson(s)).toList(),
      );
}

/// Fravær (sykdom, ferie, skade) – økter i perioden regnes ikke som tapt.
class Absence {
  final DateTime from;
  DateTime to;
  final String reason;
  int appliedSteps; // hvor mange nivåsteg planen ble satt ned

  Absence({required DateTime from, required DateTime to, required this.reason, this.appliedSteps = 0})
      : from = dateOnly(from),
        to = dateOnly(to);

  int get days => to.difference(from).inDays + 1;

  bool contains(DateTime d) => !dateOnly(d).isBefore(from) && !dateOnly(d).isAfter(to);

  Map<String, dynamic> toJson() =>
      {'from': from.toIso8601String(), 'to': to.toIso8601String(), 'reason': reason, 'appliedSteps': appliedSteps};

  factory Absence.fromJson(Map<String, dynamic> j) => Absence(
        from: DateTime.parse(j['from']),
        to: DateTime.parse(j['to']),
        reason: j['reason'],
        appliedSteps: j['appliedSteps'] ?? 0,
      );
}

/// Endring i nivået på planen, med forklaring til brukeren.
class LevelChange {
  final DateTime date;
  final int delta;
  final String reason;
  bool seen;

  LevelChange({required DateTime date, required this.delta, required this.reason, this.seen = false})
      : date = dateOnly(date);

  Map<String, dynamic> toJson() => {'date': date.toIso8601String(), 'delta': delta, 'reason': reason, 'seen': seen};

  factory LevelChange.fromJson(Map<String, dynamic> j) =>
      LevelChange(date: DateTime.parse(j['date']), delta: j['delta'], reason: j['reason'], seen: j['seen'] ?? false);
}

class Measurement {
  final DateTime date;
  final double? weightKg;
  final double? waistCm;

  Measurement({required DateTime date, this.weightKg, this.waistCm}) : date = dateOnly(date);

  Map<String, dynamic> toJson() =>
      {'date': date.toIso8601String(), 'weightKg': weightKg, 'waistCm': waistCm};

  factory Measurement.fromJson(Map<String, dynamic> j) => Measurement(
        date: DateTime.parse(j['date']),
        weightKg: (j['weightKg'] as num?)?.toDouble(),
        waistCm: (j['waistCm'] as num?)?.toDouble(),
      );
}

class TestResult {
  final DateTime date;
  final int? squats60s;
  final int? plankSec;
  final int? walk3kmSec;
  final int? hillBreath; // 1–10

  TestResult({required DateTime date, this.squats60s, this.plankSec, this.walk3kmSec, this.hillBreath})
      : date = dateOnly(date);

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'squats60s': squats60s,
        'plankSec': plankSec,
        'walk3kmSec': walk3kmSec,
        'hillBreath': hillBreath,
      };

  factory TestResult.fromJson(Map<String, dynamic> j) => TestResult(
        date: DateTime.parse(j['date']),
        squats60s: j['squats60s'],
        plankSec: j['plankSec'],
        walk3kmSec: j['walk3kmSec'],
        hillBreath: j['hillBreath'],
      );
}

// ---------- Norsk datoformat uten ekstra pakker ----------

const ukedagerKort = ['MAN', 'TIR', 'ONS', 'TOR', 'FRE', 'LØR', 'SØN'];
const ukedager = ['mandag', 'tirsdag', 'onsdag', 'torsdag', 'fredag', 'lørdag', 'søndag'];
const maaneder = [
  'januar', 'februar', 'mars', 'april', 'mai', 'juni',
  'juli', 'august', 'september', 'oktober', 'november', 'desember'
];
const maanederKort = ['jan', 'feb', 'mar', 'apr', 'mai', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'des'];

String fmtDato(DateTime d) => '${d.day}. ${maanederKort[d.month - 1]}';
String fmtDatoLang(DateTime d) => '${d.day}. ${maaneder[d.month - 1]} ${d.year}';
String fmtUkedag(DateTime d) {
  final s = ukedager[d.weekday - 1];
  return '${s[0].toUpperCase()}${s.substring(1)} ${fmtDato(d)}';
}

String fmtKg(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

String fmtSek(int s) {
  if (s % 60 == 0) return '${s ~/ 60} min';
  if (s < 60) return '$s sek';
  return '${s ~/ 60} min ${s % 60} sek';
}


/// Det klokka faktisk registrerte for én økt.
class WatchData {
  final String id;
  final DateTime start;
  final DateTime end;
  final String activity; // f.eks. «Gåtur»
  final String source; // f.eks. Samsung Health
  final int? avgHr;
  final int? maxHr;
  final int? minHr;
  final int? kcal;
  final int? distanceM;
  final int? steps;

  /// Sekunder i pulssone 1–5 (under 60 %, 60–70, 70–80, 80–90, over 90 % av makspuls).
  final List<int> zoneSec;

  /// Snittpuls per minutt (0 = ingen måling det minuttet).
  final List<int> hrCurve;

  /// Makspulsen sonene er regnet ut fra.
  final int hrMaxUsed;

  /// Hva appen gjorde med økta (krysset av, ekstra, før planen …).
  String outcome;

  /// Sammenslått økt: id-ene til delene. Tom for vanlige økter.
  final List<String> parts;

  /// Del av en sammenslått økt: id-en til den sammenslåtte.
  String? mergedInto;

  /// Aktiv tid i sekunder for sammenslåtte økter (summen av delene, ikke pausene mellom).
  final int? activeSec;

  WatchData({
    required this.id,
    required this.start,
    required this.end,
    required this.activity,
    this.source = '',
    this.avgHr,
    this.maxHr,
    this.minHr,
    this.kcal,
    this.distanceM,
    this.steps,
    this.zoneSec = const [0, 0, 0, 0, 0],
    this.hrCurve = const [],
    this.hrMaxUsed = 160,
    this.outcome = '',
    this.parts = const [],
    this.mergedInto,
    this.activeSec,
  });

  bool get isMerged => parts.isNotEmpty;

  /// Varighet i sekunder: aktiv tid for sammenslåtte, ellers start til slutt.
  int get durationSec => activeSec ?? end.difference(start).inSeconds;

  int get minutes => durationSec ~/ 60;
  bool get hasHr => avgHr != null;

  /// Tempo i sekunder per km.
  int? get paceSecPerKm =>
      distanceM == null || distanceM! < 200 ? null : (durationSec * 1000 / distanceM!).round();

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'activity': activity,
        'source': source,
        'avgHr': avgHr,
        'maxHr': maxHr,
        'minHr': minHr,
        'kcal': kcal,
        'distanceM': distanceM,
        'steps': steps,
        'zoneSec': zoneSec,
        'hrCurve': hrCurve,
        'hrMaxUsed': hrMaxUsed,
        'outcome': outcome,
        if (parts.isNotEmpty) 'parts': parts,
        if (mergedInto != null) 'mergedInto': mergedInto,
        if (activeSec != null) 'activeSec': activeSec,
      };

  factory WatchData.fromJson(Map<String, dynamic> j) => WatchData(
        id: j['id'],
        start: DateTime.parse(j['start']),
        end: DateTime.parse(j['end']),
        activity: j['activity'] ?? '',
        source: j['source'] ?? '',
        avgHr: j['avgHr'],
        maxHr: j['maxHr'],
        minHr: j['minHr'],
        kcal: j['kcal'],
        distanceM: j['distanceM'],
        steps: j['steps'],
        zoneSec: ((j['zoneSec'] as List?) ?? const [0, 0, 0, 0, 0]).cast<int>(),
        hrCurve: ((j['hrCurve'] as List?) ?? const []).cast<int>(),
        hrMaxUsed: j['hrMaxUsed'] ?? 160,
        outcome: j['outcome'] ?? '',
        parts: ((j['parts'] as List?) ?? const []).cast<String>(),
        mergedInto: j['mergedInto'],
        activeSec: j['activeSec'],
      );
}

/// «14:05»
String fmtKl(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
