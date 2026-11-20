import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treningsplan/compensation.dart';
import 'package:treningsplan/models.dart';
import 'package:treningsplan/plan_generator.dart';
import 'package:treningsplan/state.dart';

Profile hansProfil({Intensity intensity = Intensity.moderat, int days = 5}) => Profile(
      age: 67,
      heightCm: 182,
      weightKg: 95,
      targetKg: 87,
      startDate: DateTime(2026, 12, 1),
      endDate: DateTime(2027, 5, 1),
      fitness: Fitness.kanJogge,
      intensity: intensity,
      daysPerWeek: days,
      minutesPerSession: 45,
      activities: Activity.values.toSet(),
    );

List<Session> allSessions(List<WeekPlan> weeks) => [for (final w in weeks) ...w.sessions];

void main() {
  group('Plangenerator', () {
    test('22 uker fra 1. desember til 1. mai', () {
      final p = hansProfil();
      expect(p.totalWeeks, 22);
      final weeks = generatePlan(p);
      expect(weeks.length, 22);
      expect(allSessions(weeks).first.date.isBefore(p.startDate), isFalse);
      expect(allSessions(weeks).last.date.isAfter(p.endDate), isFalse);
    });

    test('vektmål gir ca. 0,36 kg per uke og ca. 400 kcal underskudd', () {
      final p = hansProfil();
      expect(p.kgPerWeek, closeTo(0.36, 0.01));
      expect(p.dailyDeficitKcal, inInclusiveRange(380, 420));
      expect(p.goalTooAggressive, isFalse);
    });

    for (final days in [3, 4, 5, 6]) {
      for (final intensity in Intensity.values) {
        test('aldri harde økter to dager på rad ($days dager, ${intensity.name})', () {
          final s = allSessions(generatePlan(hansProfil(days: days, intensity: intensity)));
          final hard = s.where((x) => x.isHard).map((x) => x.date).toList();
          for (var i = 1; i < hard.length; i++) {
            expect(hard[i].difference(hard[i - 1]).inDays, greaterThan(1));
          }
        });

        test('maks 10 % økning per uke ($days dager, ${intensity.name})', () {
          final weeks = generatePlan(hansProfil(days: days, intensity: intensity));
          WeekPlan? ref;
          for (final w in weeks.where((w) => !w.deload)) {
            if (ref != null && ref.sessions.length == w.sessions.length) {
              expect(w.load, lessThanOrEqualTo(ref.load * 1.10 + 0.01), reason: 'uke ${w.index + 1}');
            }
            ref = w;
          }
        });
      }
    }

    test('lettuker har lavere belastning enn uka før', () {
      final weeks = generatePlan(hansProfil());
      for (final w in weeks.where((w) => w.deload && w.index > 1 && w.phase != 'Testuke')) {
        expect(w.load, lessThan(weeks[w.index - 1].load), reason: 'uke ${w.index + 1}');
      }
    });

    test('intervallene blir lengre utover vinteren', () {
      final weeks = generatePlan(hansProfil());
      int work(WeekPlan w) {
        final s = w.sessions.firstWhere((s) => s.type == SessionType.motbakke);
        return s.reps * s.workSec;
      }

      expect(work(weeks[17]), greaterThan(work(weeks[1]) * 2));
      expect(weeks.first.phase, 'Tilvenning');
      expect(weeks.last.phase, 'Testuke');
    });

    test('CrossFit-sirklene roterer og starter med 30/30', () {
      final weeks = generatePlan(hansProfil());
      final b = [for (final w in weeks) w.sessions.where((s) => s.type == SessionType.styrkeB).firstOrNull];
      expect(b[0]!.workSec, 30);
      expect(b[5]!.workSec, 40);
      expect({b[4]!.circuit, b[5]!.circuit, b[6]!.circuit}, {1, 2, 3});
    });
  });

  group('Tapt økt', () {
    late Profile p;
    late List<WeekPlan> weeks;
    setUp(() {
      p = hansProfil();
      weeks = generatePlan(p);
    });

    Session sessionOn(DateTime d) => allSessions(weeks).firstWhere((s) => s.date == d);

    test('langtur onsdag flyttes til fredag og kortes ned', () {
      final missed = sessionOn(DateTime(2026, 12, 16))..status = SessionStatus.staattOver;
      expect(missed.type, SessionType.langtur);
      final opts = compensationOptions(weeks: weeks, profile: p, missed: missed, today: DateTime(2026, 12, 17));
      final flytt = opts.firstWhere((o) => o.kind == CompKind.flytt);
      expect(flytt.recommended, isTrue);
      flytt.apply(weeks, p, missed);
      final moved = sessionOn(DateTime(2026, 12, 18));
      expect(moved.type, SessionType.langtur);
      expect(moved.minutes, lessThan(missed.minutes));
      expect(missed.resolved, isTrue);
    });

    test('tapte intervaller legges aldri inntil en annen hard økt', () {
      for (final w in weeks.take(20)) {
        final m = w.sessions.where((s) => s.type == SessionType.motbakke).firstOrNull;
        if (m == null) continue;
        final ws = generatePlan(p);
        final missed = allSessions(ws).firstWhere((s) => s.id == m.id)..status = SessionStatus.staattOver;
        final opts = compensationOptions(
            weeks: ws, profile: p, missed: missed, today: missed.date.add(const Duration(days: 1)));
        final flytt = opts.where((o) => o.kind == CompKind.flytt).firstOrNull;
        if (flytt == null) continue;
        flytt.apply(ws, p, missed);
        final hard = allSessions(ws).where((s) => s.isHard && s.status != SessionStatus.staattOver).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        for (var i = 1; i < hard.length; i++) {
          expect(hard[i].date.difference(hard[i - 1].date).inDays, greaterThan(1));
        }
      }
    });

    test('fordel tilbys ikke inn i en lettuke', () {
      // Uka etter 17. des (21.–27. des) er lettuke.
      final missed = sessionOn(DateTime(2026, 12, 16))..status = SessionStatus.staattOver;
      final opts = compensationOptions(weeks: weeks, profile: p, missed: missed, today: DateTime(2026, 12, 17));
      expect(weeks[3].deload, isTrue);
      expect(opts.where((o) => o.kind == CompKind.fordel), isEmpty);
    });

    test('fordeling holder neste uke innenfor 10 % av forrige vanlige uke', () {
      // Tapt langtur 30. des, i dag 1. jan: neste uke (4.–10. jan) er vanlig uke.
      final missed = sessionOn(DateTime(2026, 12, 30))..status = SessionStatus.staattOver;
      final next = weeks[5];
      final before = next.plannedLoad;
      final opts = compensationOptions(weeks: weeks, profile: p, missed: missed, today: DateTime(2027, 1, 1));
      final fordel = opts.firstWhere((o) => o.kind == CompKind.fordel);
      fordel.apply(weeks, p, missed);
      expect(next.plannedLoad, greaterThan(before));
      expect(next.plannedLoad, lessThanOrEqualTo(loadLimit(weeks, next, startDate: p.startDate)! + 0.01));
      expect(safetyViolations(weeks, startDate: p.startDate), isEmpty);
    });

    test('stryk holder progresjonen igjen for kommende uker', () {
      final missed = sessionOn(DateTime(2026, 12, 16))..status = SessionStatus.staattOver;
      final before = weeks.map((w) => w.progression).toList();
      final opts = compensationOptions(weeks: weeks, profile: p, missed: missed, today: DateTime(2026, 12, 17));
      opts.firstWhere((o) => o.kind == CompKind.stryk).apply(weeks, p, missed);
      for (final w in weeks) {
        if (w.index <= 2) {
          expect(w.progression, before[w.index]);
        } else if (before[w.index] > 0) {
          expect(w.progression, before[w.index] - 1);
        }
      }
    });
  });

  group('App-tilstand', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    setUp(() => SharedPreferences.setMockInitialValues({}));
    test('uavkryssede økter blir stått over, og tre på to uker gir tilbakesteg', () {
      var now = DateTime(2026, 12, 1);
      final app = AppState(clock: () => now);
      app.createPlan(hansProfil());
      final progBefore = app.weeks[3].progression;
      // Trener første uke, så tre økter tapt i uke 2 (ikke langt fravær).
      for (final s in app.weeks[0].sessions) {
        s.status = SessionStatus.fullfort;
      }
      app.markDone(app.weeks[1].sessions.first);
      now = DateTime(2026, 12, 12);
      app.refreshMissed();
      final missed = app.unresolvedMissed;
      expect(missed.length, greaterThanOrEqualTo(3));
      // Tilbakesteget skjer før brukeren får forslag – med forklaring.
      expect(app.weeks[3].progression, progBefore - 1);
      expect(app.unseenChanges.single.delta, -1);
      // Et valgt forslag blir ikke overskrevet etterpå.
      final m = missed.first;
      final o = app.optionsFor(m).firstWhere((o) => o.kind != CompKind.stryk);
      app.applyCompensation(o, m);
      expect(app.weeks[3].progression, progBefore - 1);
      expect(m.resolved, isTrue);
    });

    test('lagring og lesing gir samme plan', () {
      final app = AppState(clock: () => DateTime(2026, 12, 1));
      app.createPlan(hansProfil());
      final json = app.toJson();
      final copy = AppState(clock: () => DateTime(2026, 12, 1))..fromJson(json);
      expect(copy.weeks.length, app.weeks.length);
      expect(copy.weeks[5].sessions.map((s) => s.minutes), app.weeks[5].sessions.map((s) => s.minutes));
      expect(copy.profile!.targetKg, 87);
    });
  });
}
