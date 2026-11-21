import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treningsplan/models.dart';
import 'package:treningsplan/plan_generator.dart';
import 'package:treningsplan/state.dart';
import 'package:treningsplan/watch_import.dart';

import 'plan_test.dart' show hansProfil;

ImportedWorkout gaatur(DateTime start, {int min = 60, String id = 'w1', double bpm = 110}) => ImportedWorkout(
      id: id,
      start: start,
      end: start.add(Duration(minutes: min)),
      activity: WatchActivity.gange,
      distanceM: 6000,
      steps: 7200,
      kcal: 380,
      source: 'com.sec.android.app.shealth',
      // Måling hvert 30. sek, de første 10 min lavere puls.
      hrSamples: [
        for (var s = 0; s < min * 60; s += 30)
          (start.add(Duration(seconds: s)), s < 600 ? 90.0 : bpm)
      ],
    );

void main() {
  test('pulssoner, snitt og kurve regnes ut riktig', () {
    final d = watchDataFor(gaatur(DateTime(2026, 12, 5, 14)), 160);
    expect(d.minutes, 60);
    expect(d.zoneSec.reduce((a, b) => a + b), 3600);
    // 90/160 = 56 % → sone 1 i 10 min, 110/160 = 69 % → sone 2 i 50 min
    expect(d.zoneSec[0], 600);
    expect(d.zoneSec[1], 3000);
    expect(d.avgHr, ((90 * 600 + 110 * 3000) / 3600).round());
    expect(d.maxHr, 110);
    expect(d.minHr, 90);
    expect(d.hrCurve.length, 60);
    expect(d.hrCurve.first, 90);
    expect(d.paceSecPerKm, 600); // 60 min på 6 km = 10:00 min/km
  });

  test('økt fra klokka lagres og kobles til planlagt økt, også før planstart', () async {
    SharedPreferences.setMockInitialValues({});
    var now = DateTime(2026, 11, 21, 18);
    final app = AppState(clock: () => now);
    await app.load();
    app.createPlan(hansProfil());
    // Før planen starter (1. des): vises, men påvirker ikke planen.
    app.importFromWatch([gaatur(DateTime(2026, 11, 21, 14), id: 'for')]);
    expect(app.watchDataById('for')!.outcome, contains('Før planen'));
    expect(app.weeks.expand((w) => w.sessions).any((s) => s.watchId == 'for'), isFalse);

    now = DateTime(2026, 12, 9, 20); // onsdag = langtur
    final lang = app.weeks.expand((w) => w.sessions).firstWhere((s) => s.date == DateTime(2026, 12, 9));
    app.importFromWatch([gaatur(DateTime(2026, 12, 9, 10), id: 'ons', min: lang.minutes)]);
    expect(lang.watchId, 'ons');
    expect(lang.status, SessionStatus.fullfort);
    expect(app.watchDataById('ons')!.outcome, contains('Krysset av'));

    // Lagres og leses inn igjen
    final copy = AppState(clock: () => now);
    copy.fromJson(app.toJson());
    expect(copy.watchDataById('ons')!.zoneSec, app.watchDataById('ons')!.zoneSec);
    expect(copy.weeks.expand((w) => w.sessions).firstWhere((s) => s.id == lang.id).watchId, 'ons');
  });

  test('eldre import uten detaljer kobles når økta hentes på nytt', () async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime(2026, 12, 9, 20);
    final app = AppState(clock: () => now);
    await app.load();
    app.createPlan(hansProfil());
    final lang = app.weeks.expand((w) => w.sessions).firstWhere((s) => s.date == DateTime(2026, 12, 9));
    app.importFromWatch([gaatur(DateTime(2026, 12, 9, 10), id: 'gml', min: lang.minutes)]);
    // Simuler versjon uten detaljer
    lang.watchId = null;
    app.watchLog.clear();
    app.importFromWatch([gaatur(DateTime(2026, 12, 9, 10), id: 'gml', min: lang.minutes)]);
    expect(lang.watchId, 'gml');
    expect(app.watchDataById('gml')!.outcome, contains('Krysset av'));
  });

  test('start planen i dag: dagens klokkeøkt regnes med, og sikkerhetsreglene holder', () async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime(2026, 11, 21, 15, 30); // lørdag
    final app = AppState(clock: () => now);
    await app.load();
    app.createPlan(hansProfil()); // start 1. des
    expect(app.notStarted, isTrue);
    app.importFromWatch([gaatur(DateTime(2026, 11, 21, 13), id: 'idag')]);
    expect(app.watchDataById('idag')!.outcome, contains('Før planen'));

    app.startToday();
    expect(app.notStarted, isFalse);
    expect(app.profile!.startDate, DateTime(2026, 11, 21));
    expect(app.profile!.endDate, hansProfil().endDate);
    expect(safetyViolations(app.weeks, startDate: app.profile!.startDate), isEmpty);
    expect(app.measurements.where((m) => m.date == DateTime(2026, 12, 1)), isEmpty);

    app.importFromWatch([gaatur(DateTime(2026, 11, 21, 13), id: 'idag')]);
    final d = app.watchDataById('idag')!;
    expect(d.outcome, isNot(contains('Før planen')));
    expect(app.weeks.expand((w) => w.sessions).where((s) => s.watchId == 'idag'), hasLength(1));
  });
}
