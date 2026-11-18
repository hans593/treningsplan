// Datamodeller for treningsplanen.

enum Intensity { rolig, moderat, krevende }

enum Fitness { liteAktiv, gaarRaskt, kanJogge, trenerJevnlig }

enum Activity { manualer, raskGange, motbakker, jogging }

enum SessionType { motbakke, styrkeA, styrkeB, langtur, kondisjon, restitusjon }

enum Effort { lett, moderat, hard }

enum SessionStatus { planlagt, fullfort, staattOver }

enum Feeling { forLett, passe, forTungt }

/// Hvordan en stått-over-økt ble håndtert.
enum Resolution { forOppstart, flyttet, fordelt, strokket, ekstraOkt }

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
  })  : startDate = dateOnly(startDate),
        endDate = dateOnly(endDate);

  int get totalWeeks {
    final days = endDate.difference(startDate).inDays;
    return ((days + 1) / 7).ceil().clamp(1, 104);
  }

  double get kgPerWeek => (weightKg - targetKg) / totalWeeks;

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
      );
}

class Session {
  final String id;
  DateTime date;
  final SessionType type;
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
  }) : date = dateOnly(date);

  bool get isHard => effort == Effort.hard;

  Category get category => categoryOf(type);

  /// Tapt økt som teller med i regelen om tre tapte økter på to uker.
  bool get countsAsMissed =>
      status == SessionStatus.staattOver &&
      resolution != Resolution.forOppstart &&
      resolution != Resolution.ekstraOkt;

  /// Kan registreres som gjennomført i ettertid (på sin egen dato).
  bool get canBackRegister =>
      !extra &&
      status == SessionStatus.staattOver &&
      (resolution == null || resolution == Resolution.forOppstart || resolution == Resolution.strokket);

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
      );
}

class WeekPlan {
  final int index; // 0-basert
  final DateTime monday;
  int progression; // nivå i progresjonsstigen
  final bool deload;
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
