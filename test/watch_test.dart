import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treningsplan/models.dart';
import 'package:treningsplan/state.dart';
import 'package:treningsplan/watch_import.dart';

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
    for (final w in app.weeks) {
      for (final s in w.sessions) {
        if (s.date.isBefore(DateTime(2026, 12, 14))) s.status = SessionStatus.fullfort;
      }
    }
  });

  Session planned(DateTime d) =>
      [for (final w in app.weeks) ...w.sessions].firstWhere((s) => !s.extra && s.date == d);

  ImportedWorkout w(String id, DateTime start, int min, WatchActivity a, {double? avg, double? max}) =>
      ImportedWorkout(id: id, start: start, end: start.add(Duration(minutes: min)), activity: a, avgHr: avg, maxHr: max);

  test('gåtur samme dag krysser av planlagt langtur', () {
    now = DateTime(2026, 12, 16, 20);
    final r = app.importFromWatch([w('a', DateTime(2026, 12, 16, 10), 62, WatchActivity.gange, avg: 105)]);
    final wed = planned(DateTime(2026, 12, 16));
    expect(wed.status, SessionStatus.fullfort);
    expect(wed.note, startsWith('Fra klokka'));
    expect(r.markedDone, 1);
    expect(r.extras, 0);
  });

  test('motbakkeøkt med høy makspuls krysser av intervalløkta', () {
    now = DateTime(2026, 12, 14, 20);
    // 67 år: makspuls ca. 161. Topper på 145 = 90 %.
    app.importFromWatch([w('b', DateTime(2026, 12, 14, 9), 48, WatchActivity.gange, avg: 118, max: 145)]);
    expect(planned(DateTime(2026, 12, 14)).status, SessionStatus.fullfort);
  });

  test('rolig tur krysser ikke av intervaller, men blir ekstra', () {
    now = DateTime(2026, 12, 14, 20);
    final r = app.importFromWatch([w('c', DateTime(2026, 12, 14, 9), 50, WatchActivity.gange, avg: 95, max: 110)]);
    expect(planned(DateTime(2026, 12, 14)).status, SessionStatus.planlagt);
    expect(r.extras, 1);
  });

  test('styrkeøkt fra klokka krysser av styrkeøkta', () {
    now = DateTime(2026, 12, 15, 20);
    app.importFromWatch([w('d', DateTime(2026, 12, 15, 18), 30, WatchActivity.styrke)]);
    expect(planned(DateTime(2026, 12, 15)).status, SessionStatus.fullfort);
  });

  test('synk dager senere: krysser av på riktig dato og tar igjen tapte økter', () {
    now = DateTime(2026, 12, 19, 12);
    app.refreshMissed();
    final r = app.importFromWatch([
      w('e', DateTime(2026, 12, 15, 18), 32, WatchActivity.styrke), // tirsdag, gjort på dagen
      w('f', DateTime(2026, 12, 17, 11), 70, WatchActivity.gange, avg: 100), // torsdag, langtur var onsdag
    ]);
    expect(planned(DateTime(2026, 12, 15)).status, SessionStatus.fullfort);
    final wed = planned(DateTime(2026, 12, 16));
    expect(wed.status, SessionStatus.staattOver);
    expect(wed.resolution, Resolution.ekstraOkt);
    expect(r.markedDone, 1);
    expect(r.extras, 1);
    expect(r.covered, 1);
  });

  test('samme økt hentes ikke to ganger', () {
    now = DateTime(2026, 12, 17, 20);
    final x = w('g', DateTime(2026, 12, 17, 7), 40, WatchActivity.lop, avg: 125);
    app.importFromWatch([x]);
    final r2 = app.importFromWatch([x]);
    expect(r2.isEmpty, isTrue);
    expect(app.extrasDone + (planned(DateTime(2026, 12, 17)).status == SessionStatus.fullfort ? 1 : 0), 1);
  });

  test('korte økter og økter før planen hoppes over', () {
    now = DateTime(2026, 12, 17, 20);
    final r = app.importFromWatch([
      w('h', DateTime(2026, 12, 17, 7), 6, WatchActivity.gange),
      w('i', DateTime(2026, 11, 20, 7), 60, WatchActivity.gange),
    ]);
    expect(r.isEmpty, isTrue);
    expect(app.importedWorkoutIds, containsAll(['h', 'i']));
  });

  test('anstrengelse fra puls', () {
    // makspuls 67 år ≈ 161
    expect(effortFor(w('x', now, 40, WatchActivity.lop, avg: 95), 67), Effort.lett);
    expect(effortFor(w('x', now, 40, WatchActivity.lop, avg: 115), 67), Effort.moderat);
    expect(effortFor(w('x', now, 40, WatchActivity.lop, avg: 130), 67), Effort.hard);
    expect(effortFor(w('x', now, 40, WatchActivity.gange), 67), Effort.lett);
  });

  test('vekt fra smartvekt legges inn én gang per dag', () {
    now = DateTime(2026, 12, 17, 20);
    final r = app.importFromWatch([], weights: [
      (DateTime(2026, 12, 10, 7), 94.6),
      (DateTime(2026, 12, 10, 21), 95.1),
      (DateTime(2026, 12, 17, 7), 94.2),
    ]);
    expect(r.weights, 2);
    expect(app.latestWeight, 94.2);
    expect(app.measurements.firstWhere((m) => m.date == DateTime(2026, 12, 10)).weightKg, 95.1);
  });
}
