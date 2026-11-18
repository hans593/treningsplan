import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treningsplan/models.dart';
import 'package:treningsplan/state.dart';

import 'plan_test.dart' show hansProfil;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late DateTime now;
  late AppState app;
  setUp(() {
    now = DateTime(2026, 12, 1);
    app = AppState(clock: () => now);
    app.createPlan(hansProfil());
  });

  /// Marker alle planlagte økter før [d] som gjort, så testen bare ser én tapt økt.
  void doneUntil(DateTime d) {
    for (final w in app.weeks) {
      for (final s in w.sessions) {
        if (s.date.isBefore(d)) s.status = SessionStatus.fullfort;
      }
    }
  }

  Session planned(DateTime d) =>
      [for (final w in app.weeks) ...w.sessions].firstWhere((s) => !s.extra && s.date == d);

  group('Ekstra økter', () {
    test('ikke gjennomført innen datoen regnes som ikke utført', () {
      now = DateTime(2026, 12, 17);
      app.refreshMissed();
      final wed = planned(DateTime(2026, 12, 16));
      expect(wed.status, SessionStatus.staattOver);
      expect(app.unresolvedMissed, contains(wed));
    });

    test('ekstra tur dagen etter tar igjen tapt langtur', () {
      doneUntil(DateTime(2026, 12, 16));
      now = DateTime(2026, 12, 17);
      app.refreshMissed();
      final wed = planned(DateTime(2026, 12, 16));
      final covered = app.addExtra(
          date: DateTime(2026, 12, 17), type: SessionType.langtur, title: 'Tur', minutes: wed.minutes, effort: Effort.lett);
      expect(covered, [wed]);
      expect(wed.resolved, isTrue);
      expect(wed.resolution, Resolution.ekstraOkt);
      expect(app.unresolvedMissed, isNot(contains(wed)));
    });

    test('for kort eller feil type tar ikke igjen, men regnes med', () {
      doneUntil(DateTime(2026, 12, 16));
      now = DateTime(2026, 12, 17);
      app.refreshMissed();
      final wed = planned(DateTime(2026, 12, 16));
      final week = app.weekFor(wed.date)!;
      final loadBefore = week.load;
      expect(app.addExtra(date: now, type: SessionType.langtur, title: 'Kort tur', minutes: 20, effort: Effort.lett), isEmpty);
      expect(app.addExtra(date: now, type: SessionType.styrkeA, title: 'Styrke', minutes: 60, effort: Effort.moderat), isEmpty);
      expect(wed.resolved, isFalse);
      expect(week.load, greaterThan(loadBefore));
      expect(app.extrasDone, 2);
    });

    test('ekstra økt tidligere i uka dekker en økt som blir stått over senere', () {
      doneUntil(DateTime(2026, 12, 16));
      now = DateTime(2026, 12, 15);
      app.addExtra(date: now, type: SessionType.langtur, title: 'Lang tur', minutes: 90, effort: Effort.lett);
      now = DateTime(2026, 12, 17);
      app.refreshMissed();
      final wed = planned(DateTime(2026, 12, 16));
      expect(wed.resolution, Resolution.ekstraOkt);
    });

    test('intervaller tas ikke igjen med rolig tur', () {
      doneUntil(DateTime(2026, 12, 14));
      now = DateTime(2026, 12, 15);
      app.refreshMissed();
      final mon = planned(DateTime(2026, 12, 14));
      expect(mon.isHard, isTrue);
      expect(app.addExtra(date: now, type: SessionType.langtur, title: 'Tur', minutes: 90, effort: Effort.lett), isEmpty);
      expect(app.addExtra(date: now, type: SessionType.kondisjon, title: 'Jogg', minutes: 45, effort: Effort.moderat), [mon]);
    });

    test('slette ekstra økt gjør den tapte økta åpen igjen', () {
      now = DateTime(2026, 12, 17);
      app.refreshMissed();
      final wed = planned(DateTime(2026, 12, 16));
      app.addExtra(date: now, type: SessionType.langtur, title: 'Tur', minutes: 80, effort: Effort.lett);
      final extra = app.weekFor(now)!.sessions.firstWhere((s) => s.extra);
      app.deleteExtra(extra);
      expect(wed.resolved, isFalse);
      expect(app.unresolvedMissed, contains(wed));
    });

    test('ekstra økter i fremtiden avvises', () {
      expect(
          () => app.addExtra(
              date: DateTime(2026, 12, 5), type: SessionType.langtur, title: 'x', minutes: 30, effort: Effort.lett),
          throwsArgumentError);
    });

    test('tatt igjen med ekstra økt teller ikke som tapt i tilbakestegsregelen', () {
      now = DateTime(2026, 12, 13);
      app.refreshMissed();
      final missed = [for (final w in app.weeks) ...w.sessions].where((s) => s.status == SessionStatus.staattOver).toList();
      for (final m in missed) {
        app.addExtra(date: m.date.add(const Duration(days: 1)), type: m.type, title: 'Ekstra', minutes: m.minutes + 10, effort: Effort.hard);
      }
      expect(missed.every((m) => m.resolution == Resolution.ekstraOkt), isTrue);
      expect(missed.where((m) => m.countsAsMissed), isEmpty);
    });
  });

  group('Etterregistrering', () {
    test('tapt økt kan registreres som gjennomført på sin egen dato', () {
      now = DateTime(2026, 12, 20);
      app.refreshMissed();
      final wed = planned(DateTime(2026, 12, 16));
      expect(wed.canBackRegister, isTrue);
      app.backRegister(wed);
      expect(wed.status, SessionStatus.fullfort);
      expect(wed.date, DateTime(2026, 12, 16));
      expect(app.unresolvedMissed, isNot(contains(wed)));
    });

    test('økter før oppstart kan etterregistreres', () {
      now = DateTime(2026, 12, 9);
      final late = AppState(clock: () => now)..createPlan(hansProfil());
      final tue = [for (final w in late.weeks) ...w.sessions].firstWhere((s) => s.date == DateTime(2026, 12, 1));
      expect(tue.resolution, Resolution.forOppstart);
      expect(late.unresolvedMissed, isEmpty);
      late.backRegister(tue);
      expect(tue.status, SessionStatus.fullfort);
    });

    test('ekstra økt kan registreres tilbake i tid og tar igjen', () {
      doneUntil(DateTime(2026, 12, 16));
      now = DateTime(2026, 12, 21);
      app.refreshMissed();
      final wed = planned(DateTime(2026, 12, 16));
      final covered = app.addExtra(
          date: DateTime(2026, 12, 18), type: SessionType.langtur, title: 'Tur', minutes: 70, effort: Effort.lett);
      expect(covered, contains(wed));
      expect(app.weekFor(DateTime(2026, 12, 18))!.sessions.any((s) => s.extra && s.date == DateTime(2026, 12, 18)),
          isTrue);
    });
  });

  group('Justere mål', () {
    test('tidligere uker og registreringer beholdes, kommende uker endres', () {
      now = DateTime(2026, 12, 17);
      app.refreshMissed();
      app.markDone(planned(DateTime(2026, 12, 15)));
      app.addExtra(date: now, type: SessionType.langtur, title: 'Tur', minutes: 70, effort: Effort.lett);
      final before = app.weeks.take(3).map((w) => w.sessions.map((s) => '${s.id}${s.status}${s.minutes}').join()).toList();
      final progBefore = app.weeks[2].progression;

      final p = hansProfil(days: 4);
      app.adjustPlan(
        Profile(
          age: 67, heightCm: 182, weightKg: 93, targetKg: 85,
          startDate: DateTime(2026, 12, 10), endDate: DateTime(2027, 6, 1),
          fitness: p.fitness, intensity: Intensity.krevende, daysPerWeek: 4, minutesPerSession: 45,
          activities: p.activities,
        ),
        currentWeightKg: 93,
      );
      // Uke 1–3 uendret
      expect(app.weeks.take(3).map((w) => w.sessions.map((s) => '${s.id}${s.status}${s.minutes}').join()).toList(), before);
      // Startdato og startvekt ligger fast, nytt mål og ny sluttdato
      expect(app.profile!.startDate, DateTime(2026, 12, 1));
      expect(app.profile!.weightKg, 95);
      expect(app.profile!.targetKg, 85);
      expect(app.weeks.length, app.profile!.totalWeeks);
      expect(app.weeks.length, greaterThan(22));
      // 4 dager i uka fra uke 4
      expect(app.weeks[4].sessions.length, 4);
      // Nivået fortsetter jevnt (ingen hopp tilbake til start)
      expect(app.weeks[4].progression, greaterThanOrEqualTo(progBefore));
      // Måling lagt til
      expect(app.latestWeight, 93);
    });

    test('belastningen hopper ikke mer enn 10 % ved justering', () {
      now = DateTime(2027, 1, 14);
      app.refreshMissed();
      final p = hansProfil();
      app.adjustPlan(Profile(
        age: 67, heightCm: 182, weightKg: 95, targetKg: 87,
        startDate: p.startDate, endDate: DateTime(2027, 4, 1),
        fitness: p.fitness, intensity: p.intensity, daysPerWeek: 5, minutesPerSession: 45, activities: p.activities,
      ));
      final cw = app.weekFor(now)!.index;
      final next = app.weeks.skip(cw + 1).firstWhere((w) => !w.deload);
      final ref = app.weeks.take(cw + 1).lastWhere((w) => !w.deload);
      expect(next.load, lessThanOrEqualTo(ref.load * 1.10 + 0.01));
    });

    test('starte helt på nytt kan beholde vekthistorikk', () {
      app.addMeasurement(Measurement(date: DateTime(2026, 12, 1), weightKg: 95));
      app.reset(keepHistory: true);
      expect(app.profile, isNull);
      expect(app.weeks, isEmpty);
      expect(app.measurements, isNotEmpty);
      app.reset();
      expect(app.measurements, isEmpty);
    });
  });
}
