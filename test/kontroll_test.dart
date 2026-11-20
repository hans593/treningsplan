// Regresjonstester fra den uavhengige kontrollen (november 2026).
// Hver test gjenskaper et funn og sjekker at trygghetsreglene holder:
// maks 10 % økning per uke, lettuker ikke tyngre, aldri harde økter to dager på rad.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treningsplan/compensation.dart';
import 'package:treningsplan/exercises.dart';
import 'package:treningsplan/models.dart';
import 'package:treningsplan/plan_generator.dart';
import 'package:treningsplan/state.dart';
import 'package:treningsplan/watch_import.dart';
import 'package:treningsplan/workout_steps.dart';

Profile hans({int days = 5, Intensity i = Intensity.moderat, int min = 45, List<int>? trainingDays, Set<Activity>? act}) =>
    Profile(
      age: 67,
      heightCm: 182,
      weightKg: 95,
      targetKg: 87,
      startDate: DateTime(2026, 11, 30),
      endDate: DateTime(2027, 5, 1),
      fitness: Fitness.gaarRaskt,
      intensity: i,
      daysPerWeek: days,
      minutesPerSession: min,
      activities: act ?? {Activity.manualer, Activity.raskGange, Activity.motbakker, Activity.benk},
      trainingDays: trainingDays,
    );

void doneUntil(AppState app, DateTime d) {
  for (final w in app.weeks) {
    for (final s in w.sessions) {
      if (s.date.isBefore(d)) {
        s.status = SessionStatus.fullfort;
        s.resolved = true;
      }
    }
  }
}

void expectSafe(AppState app) {
  final from = firstFutureWeekIndex(app.weeks, app.today);
  expect(safetyViolations(app.weeks, fromIndex: from, startDate: app.profile!.startDate), isEmpty);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Funn 1–3: fordel og tilbakesteg', () {
    test('fordel av en hel tapt uke holder 10 %-grensen samlet', () {
      var now = DateTime(2026, 11, 30, 8);
      final app = AppState(clock: () => now);
      app.createPlan(hans());
      doneUntil(app, DateTime(2026, 12, 21));
      now = DateTime(2026, 12, 28, 8); // hele uke 4 (lettuke) er tapt
      app.refreshMissed();
      for (final m in List.of(app.unresolvedMissed)) {
        final f = app.optionsFor(m).where((o) => o.kind == CompKind.fordel).firstOrNull;
        if (f == null) continue; // ikke plass innenfor grensen: ingen fordeling tilbys
        app.applyCompensation(f, m);
      }
      expectSafe(app);
    });

    test('fordel tilbys når det er plass, og flere fordelinger deler samme grense', () {
      var now = DateTime(2026, 11, 30, 8);
      final app = AppState(clock: () => now);
      app.createPlan(hans());
      doneUntil(app, DateTime(2027, 1, 4));
      // To «for tung» gir et lavere nivå og plass under grensen.
      now = DateTime(2027, 1, 4, 20);
      app.markDone(app.weeks[5].sessions[0], feeling: Feeling.forTungt);
      now = DateTime(2027, 1, 7, 20);
      app.markDone(app.weeks[5].sessions[1], feeling: Feeling.forTungt);
      now = DateTime(2027, 1, 9, 8);
      app.refreshMissed();
      var used = 0;
      for (final m in List.of(app.unresolvedMissed)) {
        final f = app.optionsFor(m).where((o) => o.kind == CompKind.fordel).firstOrNull;
        if (f == null) continue;
        app.applyCompensation(f, m);
        used++;
        expectSafe(app);
      }
      expect(used, greaterThan(0));
    });

    test('tapt økt fra en uke som er passert gir ikke «fordel», og «stryk» er anbefalt', () {
      var now = DateTime(2026, 11, 30, 8);
      final app = AppState(clock: () => now);
      app.createPlan(hans());
      doneUntil(app, DateTime(2026, 12, 28));
      now = DateTime(2027, 1, 11, 8);
      app.refreshMissed();
      final old = [for (final w in app.weeks) ...w.sessions].firstWhere((s) => s.date == DateTime(2026, 12, 28));
      old.resolved = false;
      old.resolution = null;
      final opts = app.optionsFor(old);
      expect(opts.where((o) => o.kind == CompKind.fordel), isEmpty);
      expect(opts.firstWhere((o) => o.recommended).kind, CompKind.stryk);
    });

    test('valgt fordeling blir ikke overskrevet av tilbakesteg', () {
      var now = DateTime(2026, 11, 30, 8);
      final app = AppState(clock: () => now);
      app.createPlan(hans());
      doneUntil(app, DateTime(2026, 12, 14));
      now = DateTime(2026, 12, 20, 8); // man–lør i uke 3 tapt
      app.refreshMissed(); // tilbakesteg skjer her
      final m = [for (final w in app.weeks) ...w.sessions].firstWhere((s) => s.type == SessionType.langtur && s.date == DateTime(2026, 12, 16));
      final f = app.optionsFor(m).where((o) => o.kind == CompKind.fordel).firstOrNull;
      if (f != null) {
        app.applyCompensation(f, m);
        final added = app.weeks.expand((w) => w.sessions).where((s) => s.addedMin > 0).toList();
        expect(added, isNotEmpty);
        // En ny utregning (f.eks. «for tung» to ganger) beholder minuttene.
        regenerateFrom(app.profile!, app.weeks, firstFutureWeekIndex(app.weeks, app.today));
        expect(app.weeks.expand((w) => w.sessions).where((s) => s.addedMin > 0), isNotEmpty);
      }
      expectSafe(app);
    });

    test('«stryk» setter nivået ned maks én gang per uke', () {
      var now = DateTime(2026, 11, 30, 8);
      final app = AppState(clock: () => now);
      app.createPlan(hans());
      final before = app.weeks[10].progression;
      doneUntil(app, DateTime(2026, 12, 14));
      app.markDone(app.weeks[2].sessions.first); // ikke langt fravær
      now = DateTime(2026, 12, 19, 8);
      app.refreshMissed();
      for (final m in List.of(app.unresolvedMissed)) {
        app.applyCompensation(app.optionsFor(m).firstWhere((o) => o.kind == CompKind.stryk), m);
      }
      expect(app.weeks[10].progression, greaterThanOrEqualTo(before - 1));
      expectSafe(app);
    });
  });

  group('Funn 4: fravær', () {
    test('tre uker borte: ett samlet forslag, ingen automatisk tilbakesteg, ingen 15 % hopp', () {
      var now = DateTime(2026, 11, 30, 8);
      final app = AppState(clock: () => now);
      app.createPlan(hans());
      doneUntil(app, DateTime(2026, 12, 21));
      final progBefore = app.weeks[7].progression;
      now = DateTime(2027, 1, 11, 8);
      app.refreshMissed();
      final sug = app.suggestedAbsence;
      expect(sug, isNotNull);
      expect(app.lastSetback, isNull, reason: 'tilbakesteg venter på fravær');
      app.registerAbsence(sug!.from, sug.to, 'Sykdom');
      expect(app.unresolvedMissed, isEmpty);
      expect(app.weeks.expand((w) => w.sessions).where((s) => s.countsAsMissed), isEmpty);
      final back = app.weekFor(now)!;
      expect(back.deload, isTrue);
      expect(app.weeks[7].progression, lessThanOrEqualTo(progBefore - 2));
      expect(app.unseenChanges.last.reason, contains('Fravær'));
      // Belastningen ved retur er ikke høyere enn siste uke du trente.
      final lastTrained = app.weeks[2];
      expect(back.plannedLoad, lessThanOrEqualTo(lastTrained.plannedLoad));
      expectSafe(app);
    });

    test('planlagt ferie frem i tid, og avslutning før tiden', () {
      var now = DateTime(2026, 12, 7, 8);
      final app = AppState(clock: () => now);
      app.createPlan(hans());
      app.registerAbsence(DateTime(2026, 12, 14), DateTime(2026, 12, 27), 'Ferie', shiftEndDate: true);
      expect(app.profile!.endDate, DateTime(2027, 5, 15));
      final inside = app.weeks.expand((w) => w.sessions).where((s) => s.date.isAfter(DateTime(2026, 12, 13)) && s.date.isBefore(DateTime(2026, 12, 28)));
      expect(inside.every((s) => s.resolution == Resolution.pause), isTrue);
      now = DateTime(2026, 12, 21, 8); // kom hjem tidligere
      app.endAbsenceNow(app.absences.single);
      final after = app.weeks.expand((w) => w.sessions).where((s) => !s.date.isBefore(now) && s.date.isBefore(DateTime(2026, 12, 28)));
      expect(after.every((s) => s.status == SessionStatus.planlagt), isTrue);
      expectSafe(app);
    });

    test('fravær på over seks uker starter planen fra tilvenning', () {
      var now = DateTime(2026, 11, 30, 8);
      final app = AppState(clock: () => now);
      app.createPlan(hans());
      doneUntil(app, DateTime(2027, 1, 4));
      now = DateTime(2027, 2, 22, 8);
      app.refreshMissed();
      final s = app.suggestedAbsence!;
      app.registerAbsence(s.from, s.to, 'Skade');
      expect(app.weekFor(now)!.progression, 0);
      expectSafe(app);
    });
  });

  group('Funn 5–6: ekstraøkter og justering', () {
    test('ekstraøkter påvirker ikke 10 %-grensen for planlagte økter', () {
      var now = DateTime(2026, 12, 9, 20);
      final app = AppState(clock: () => now);
      app.createPlan(hans());
      final w = app.weeks[1];
      app.addExtra(date: DateTime(2026, 12, 8), type: SessionType.restitusjon, title: 'Annen', minutes: 60, effort: Effort.lett);
      for (var k = 0; k < 4; k++) {
        app.markDone(w.sessions.where((s) => !s.extra).elementAt(k), feeling: Feeling.forLett);
      }
      expect(safetyViolations(app.weeks, startDate: app.profile!.startDate), isEmpty);
    });

    test('mer trening ved justering trappes opp med maks 10 % per uke', () {
      var now = DateTime(2026, 11, 30, 8);
      final app = AppState(clock: () => now);
      app.createPlan(hans(days: 3, i: Intensity.rolig, min: 30));
      now = DateTime(2027, 1, 13, 8);
      doneUntil(app, now);
      app.refreshMissed();
      final r = app.adjustPlan(hans(days: 6, i: Intensity.krevende, min: 60));
      expect(r.ramped, isTrue);
      expect(app.unseenChanges.last.reason, contains('10 %'));
      expectSafe(app);
      // Litt mer trening (3 → 4 dager) når fullt antall dager innen planen
      final app2 = AppState(clock: () => DateTime(2026, 11, 30, 8));
      app2.createPlan(hans(days: 3));
      final r2 = app2.adjustPlan(hans(days: 4));
      expect(r2.ramped, isTrue);
      expect(r2.fullWeek, isNotNull, reason: 'brukeren får vite når alle fire dagene er med');
      expectSafe(app2);
    });

    test('mindre trening ved justering gjelder med en gang', () {
      var now = DateTime(2026, 11, 30, 8);
      final app = AppState(clock: () => now);
      app.createPlan(hans(days: 6, min: 60));
      now = DateTime(2027, 1, 13, 8);
      doneUntil(app, now);
      app.refreshMissed();
      expect(app.adjustPlan(hans(days: 3, min: 30)).ramped, isFalse);
      expect(app.weeks[app.firstAdjustableWeek - 0].plannedCount, lessThanOrEqualTo(3));
    });

    test('gjennomførte økter endres aldri av en ny utregning', () {
      var now = DateTime(2026, 11, 30, 8);
      final app = AppState(clock: () => now);
      app.createPlan(hans());
      now = DateTime(2027, 1, 5, 20);
      doneUntil(app, now);
      final w4 = app.weeks[3].sessions.map((s) => '${s.id}${s.minutes}').toList();
      app.markDone(app.weeks[5].sessions[0], feeling: Feeling.forTungt);
      app.markDone(app.weeks[5].sessions[1], feeling: Feeling.forTungt);
      expect(app.weeks[3].sessions.map((s) => '${s.id}${s.minutes}').toList(), w4);
    });
  });

  group('Funn 7: målinger', () {
    test('urealistiske målinger avvises, og målinger kan rettes og slettes', () {
      final app = AppState(clock: () => DateTime(2026, 12, 10));
      app.createPlan(hans());
      expect(() => app.addMeasurement(Measurement(date: DateTime(2026, 12, 10), weightKg: 9.5)), throwsArgumentError);
      expect(() => app.addMeasurement(Measurement(date: DateTime(2026, 12, 12), weightKg: 94)), throwsArgumentError);
      app.addMeasurement(Measurement(date: DateTime(2026, 12, 5), weightKg: 94.2));
      final m = app.measurements.firstWhere((x) => x.date == DateTime(2026, 12, 5));
      app.updateMeasurement(m, Measurement(date: DateTime(2026, 12, 6), weightKg: 94.0, waistCm: 104));
      expect(app.measurements.any((x) => x.date == DateTime(2026, 12, 5)), isFalse);
      final m2 = app.measurements.firstWhere((x) => x.date == DateTime(2026, 12, 6));
      app.deleteMeasurement(m2);
      expect(app.measurements.any((x) => x.date == DateTime(2026, 12, 6)), isFalse);
    });
  });

  group('Fleksibilitet', () {
    test('egne treningsdager: aldri harde økter på rad, langtur i helga når mulig', () {
      for (final days in [
        [0, 2, 4],
        [1, 3, 5, 6],
        [0, 1, 2, 3, 4],
        [0, 1, 2, 4, 5, 6],
        [2, 3, 6],
      ]) {
        final p = hans(days: days.length, trainingDays: days);
        final weeks = generatePlan(p);
        expect(safetyViolations(weeks, startDate: p.startDate), isEmpty, reason: '$days');
        final w = weeks[2];
        expect(w.sessions.map((s) => s.date.weekday - 1).toSet(), days.toSet(), reason: '$days');
        if (days.contains(5) || days.contains(6)) {
          final lang = w.sessions.firstWhere((s) => s.type == SessionType.langtur);
          expect(lang.date.weekday, greaterThanOrEqualTo(6), reason: '$days');
        }
      }
    });

    test('standarddager gir samme plan som før', () {
      final a = generatePlan(hans());
      final b = generatePlan(hans(trainingDays: [0, 1, 2, 3, 5]));
      expect(b[3].sessions.map((s) => s.id), a[3].sessions.map((s) => s.id));
    });

    test('flytte og bytte økter, men aldri harde dager på rad', () {
      final app = AppState(clock: () => DateTime(2026, 12, 7, 8));
      app.createPlan(hans());
      final w = app.weeks[1];
      final hard = w.sessions.firstWhere((s) => s.isHard);
      final opts = app.moveOptionsFor(hard);
      expect(opts, isNotEmpty);
      for (final o in opts.where((o) => o.allowed)) {
        final copy = AppState(clock: () => DateTime(2026, 12, 7, 8))..fromJson(app.toJson());
        final s = copy.weeks[1].sessions.firstWhere((x) => x.id == hard.id);
        final o2 = copy.moveOptionsFor(s).firstWhere((x) => x.date == o.date);
        expect(copy.moveSession(s, o2), isTrue);
        expect(safetyViolations(copy.weeks), isEmpty);
      }
      // Bytte tirsdag og torsdag (styrke A og B)
      final tue = w.sessions.firstWhere((s) => s.date == DateTime(2026, 12, 8));
      final thu = w.sessions.firstWhere((s) => s.date == DateTime(2026, 12, 10));
      final swap = app.moveOptionsFor(tue).firstWhere((o) => o.date == thu.date);
      expect(swap.swapWith, thu);
      app.moveSession(tue, swap);
      expect(tue.date, DateTime(2026, 12, 10));
      expect(thu.date, DateTime(2026, 12, 8));
      // Flyttingen overlever en ny utregning
      regenerateFrom(app.profile!, app.weeks, 1);
      expect(app.weeks[1].sessions.firstWhere((s) => s.id == tue.id).date, DateTime(2026, 12, 10));
    });

    test('«gjør lettere i dag» gjør bare lettere', () {
      final app = AppState(clock: () => DateTime(2026, 12, 7, 8));
      app.createPlan(hans());
      final s = app.weeks[1].sessions.firstWhere((x) => x.isHard);
      final load = s.load;
      app.easeSession(s, Ease.rolig);
      expect(s.isHard, isFalse);
      expect(s.load, lessThan(load));
      final st = app.weeks[1].sessions.firstWhere((x) => x.type == SessionType.styrkeA);
      final r = st.rounds;
      app.easeSession(st, Ease.kortere);
      expect(st.rounds, r - 1);
    });

    test('angre flytt, fordel og stryk', () {
      var now = DateTime(2026, 12, 28, 8);
      final app = AppState(clock: () => now);
      app.createPlan(hans());
      now = DateTime(2027, 1, 1, 8);
      app.refreshMissed();
      final m = app.weeks[4].sessions.firstWhere((s) => s.type == SessionType.langtur);
      final loadNext = app.weeks[5].plannedLoad;
      for (final kind in [CompKind.flytt, CompKind.fordel, CompKind.stryk]) {
        final o = app.optionsFor(m).where((o) => o.kind == kind).firstOrNull;
        if (o == null) continue;
        final prog = app.weeks[8].progression;
        app.applyCompensation(o, m);
        expect(m.resolved, isTrue);
        expect(app.undoCompensationFor(m), isNull);
        expect(m.resolved, isFalse);
        expect(app.weeks[5].plannedLoad, closeTo(loadNext, 0.01), reason: kind.name);
        expect(app.weeks[8].progression, prog, reason: kind.name);
      }
    });

    test('rette ekstraøkt: for kort tar ikke lenger igjen tapt økt', () {
      var now = DateTime(2026, 12, 14, 8);
      final app = AppState(clock: () => now);
      app.createPlan(hans());
      now = DateTime(2026, 12, 17, 20);
      app.markDone(app.weeks[2].sessions[0]);
      app.markDone(app.weeks[2].sessions[1]);
      app.refreshMissed();
      final wed = app.weeks[2].sessions.firstWhere((s) => s.date == DateTime(2026, 12, 16));
      app.addExtra(date: now, type: SessionType.langtur, title: 'Tur', minutes: wed.minutes, effort: Effort.lett);
      expect(wed.resolution, Resolution.ekstraOkt);
      final e = app.weeks[2].sessions.firstWhere((s) => s.extra);
      app.editSession(e, minutes: 20);
      expect(wed.resolved, isFalse);
    });

    test('uten manualer eller benk brukes kroppsvektøvelser', () {
      final s = generatePlan(hans(act: {Activity.motbakker}))[2].sessions.firstWhere((s) => s.type == SessionType.styrkeA);
      expect(s.title, contains('kroppsvekt'));
      final ids = exercisesFor(s, profile: hans(act: {Activity.motbakker}));
      expect(ids, isNot(contains('roing')));
      expect(ids, isNot(contains('brystpress')));
      expect(ids.toSet().length, ids.length, reason: 'ingen dobbel øvelse i samme økt');
      // Brukerens eget bytte gjelder
      final mine = exercisesFor(s, profile: hans(), swaps: {'knebøy': 'stegopp'});
      expect(mine.first, 'stegopp');
    });

    test('egen makspuls og puls som ikke kan brukes', () {
      final w = ImportedWorkout(
          id: 'x', start: DateTime(2026, 12, 7), end: DateTime(2026, 12, 7, 0, 40), activity: WatchActivity.gange, avgHr: 118, maxHr: 140);
      expect(effortFor(w, 67), Effort.hard); // 140 > 85 % av 161
      expect(effortFor(w, 67, maxHr: 175), isNot(Effort.hard));
      expect(effortFor(w, 67, ignoreHr: true), Effort.lett);
    });

    test('mål om å holde vekten gir flat vektkurve', () {
      final app = AppState(clock: () => DateTime(2026, 12, 7));
      app.createPlan(Profile(
          age: 67, heightCm: 182, weightKg: 95, targetKg: 95, startDate: DateTime(2026, 11, 30), endDate: DateTime(2027, 5, 1),
          fitness: Fitness.gaarRaskt, intensity: Intensity.moderat, daysPerWeek: 4, minutesPerSession: 45,
          activities: Activity.values.toSet(), goal: GoalType.holde));
      expect(app.plannedWeight(DateTime(2027, 3, 1)), 95);
      expect(app.profile!.kgPerWeek, 0);
    });

    test('planen er aldri lengre enn grensen, og datoene stemmer', () {
      final p = hans().copyWith(endDate: DateTime(2028, 11, 1));
      expect(generatePlan(p).length, p.totalWeeks);
      final app = AppState();
      expect(app.latestEndDate(DateTime(2026, 11, 30)).difference(DateTime(2026, 11, 30)).inDays, 7 * maxPlanWeeks - 1);
    });

    test('lengre pauser legges til alle pauser', () {
      final s = generatePlan(hans())[2].sessions.firstWhere((s) => s.type == SessionType.styrkeB);
      final normal = restSum(s, 0), longer = restSum(s, 30);
      expect(longer, greaterThan(normal));
    });
  });
}

/// Total pausetid i en guidet økt.
int restSum(Session s, int extra) =>
    stepsFor(s, extraRest: extra).where((x) => x.isRest).fold(0, (a, x) => a + (x.seconds ?? 0));
