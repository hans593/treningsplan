import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treningsplan/state.dart';
import 'package:treningsplan/watch_import.dart';

import 'plan_test.dart' show hansProfil;

/// Tur rett nordover fra Lillestrøm: 1 punkt per 10 s, ca. 1,4 m/s, opp 60 m og ned igjen.
List<(DateTime, double, double, double?)> rute(DateTime start, int min) => [
      for (var s = 0; s <= min * 60; s += 10)
        (
          start.add(Duration(seconds: s)),
          59.955 + s * 1.4 / 111195,
          11.05,
          100 + 60 * (s < min * 30 ? s / (min * 30) : 2 - s / (min * 30)) + (s % 20 == 0 ? 1.5 : -1.5),
        )
    ];

ImportedWorkout tur(DateTime start, {int min = 40, String id = 'r1'}) => ImportedWorkout(
      id: id,
      start: start,
      end: start.add(Duration(minutes: min)),
      activity: WatchActivity.gange,
      source: 'com.sec.android.app.shealth',
      hrSamples: [for (var s = 0; s < min * 60; s += 30) (start.add(Duration(seconds: s)), s < 600 ? 90.0 : 125.0)],
      route: rute(start, min),
    );

void main() {
  test('rute: distanse, stigning uten GPS-støy, pulssoner og nedsampling', () {
    final w = tur(DateTime(2026, 12, 9, 10));
    final d = watchDataFor(w, 160);
    expect(d.hasRoute, isTrue);
    expect(d.route.single.length, lessThanOrEqualTo(251));
    expect(d.route.single.first[0], closeTo(59.955, 0.00001));
    expect(d.route.single.first[2], 0); // 90/160 = 56 %
    expect(d.route.single.last[2], 2); // 125/160 = 78 %
    expect(d.ascentM, inInclusiveRange(55, 62)); // ±1,5 m støy teller ikke
    expect(d.distanceM, closeTo(40 * 60 * 1.4, 30)); // fra GPS når klokka ikke ga distanse
  });

  test('rute lagres, slås sammen og kreves tillatelse', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(clock: () => DateTime(2026, 12, 9, 20));
    await app.load();
    app.createPlan(hansProfil());
    app.importFromWatch([
      tur(DateTime(2026, 12, 9, 10), min: 20, id: 'a'),
      tur(DateTime(2026, 12, 9, 15), min: 25, id: 'b'),
      ImportedWorkout(
          id: 'c',
          start: DateTime(2026, 12, 9, 18),
          end: DateTime(2026, 12, 9, 18, 30),
          activity: WatchActivity.gange,
          routeNeedsConsent: true),
    ]);
    expect(app.watchDataById('c')!.routeNeedsConsent, isTrue);
    app.mergeWatch(['a', 'b']);
    final m = app.watchLog.firstWhere((d) => d.isMerged);
    expect(m.route.length, 2);
    expect(m.ascentM, app.watchDataById('a')!.ascentM! + app.watchDataById('b')!.ascentM!);
    final copy = AppState(clock: () => DateTime(2026, 12, 9, 20))..fromJson(app.toJson());
    expect(copy.watchDataById(m.id)!.route[1].length, m.route[1].length);
    expect(copy.watchDataById('c')!.routeNeedsConsent, isTrue);
  });
}
