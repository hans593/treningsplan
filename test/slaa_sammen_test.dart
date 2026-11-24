import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treningsplan/models.dart';
import 'package:treningsplan/plan_generator.dart';
import 'package:treningsplan/state.dart';
import 'package:treningsplan/watch_import.dart';

import 'klokkedata_test.dart' show gaatur;
import 'plan_test.dart' show hansProfil;

void main() {
  late AppState app;
  late Session lang;
  final day = DateTime(2026, 12, 9);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    app = AppState(clock: () => DateTime(2026, 12, 9, 20));
    await app.load();
    app.createPlan(hansProfil());
    lang = app.weeks.expand((w) => w.sessions).firstWhere((s) => s.date == day && !s.extra);
  });

  List<Session> extras() => app.weeks.expand((w) => w.sessions).where((s) => s.extra && s.date == day).toList();

  test('korte turer slås sammen: tid summeres, puls vektes, planen krysses av', () {
    final a = lang.minutes ~/ 3 + 2; // tre deler som hver er for korte til å krysse av langturen
    app.importFromWatch([
      gaatur(DateTime(2026, 12, 9, 10), id: 'a', min: a, bpm: 100),
      gaatur(DateTime(2026, 12, 9, 11), id: 'b', min: a, bpm: 120),
      gaatur(DateTime(2026, 12, 9, 13), id: 'c', min: 8, bpm: 110),
    ]);
    expect(lang.status, isNot(SessionStatus.fullfort));
    expect(extras().length, 2); // a og b ble ekstra, c er under 10 min

    final r = app.mergeWatch(['a', 'b', 'c']);
    final m = app.watchLog.firstWhere((d) => d.isMerged);
    expect(m.durationSec, (2 * a + 8) * 60);
    expect(m.end, DateTime(2026, 12, 9, 13, 8));
    // Vektet snitt av delenes snittpuls
    final pa = app.watchDataById('a')!, pb = app.watchDataById('b')!, pc = app.watchDataById('c')!;
    expect(m.avgHr, ((pa.avgHr! * a * 60 + pb.avgHr! * a * 60 + pc.avgHr! * 480) / m.durationSec).round());
    expect(m.zoneSec.reduce((x, y) => x + y), m.durationSec);
    expect(m.distanceM, 18000);
    expect(extras(), isEmpty);
    expect(lang.status, SessionStatus.fullfort);
    expect(lang.watchId, m.id);
    expect(r.markedDone, 1);
    expect(pa.mergedInto, m.id);
    expect(safetyViolations(app.weeks, startDate: app.profile!.startDate), isEmpty);

    // Ny henting endrer ikke noe
    app.importFromWatch([gaatur(DateTime(2026, 12, 9, 10), id: 'a', min: a, bpm: 100)]);
    expect(extras(), isEmpty);
    expect(app.watchDataById('a')!.mergedInto, m.id);

    // Lagres og leses inn
    final copy = AppState(clock: () => DateTime(2026, 12, 9, 20))..fromJson(app.toJson());
    expect(copy.watchDataById(m.id)!.parts, ['a', 'b', 'c']);
    expect(copy.watchDataById(m.id)!.durationSec, m.durationSec);

    // Del opp igjen
    app.splitWatch(m.id);
    expect(app.watchLog.any((d) => d.isMerged), isFalse);
    expect(extras().length, 2);
    expect(lang.status, isNot(SessionStatus.fullfort));
  });

  test('kan ikke slå sammen økter fra ulike dager', () {
    app.importFromWatch([
      gaatur(DateTime(2026, 12, 8, 10), id: 'x', min: 15),
      gaatur(DateTime(2026, 12, 9, 10), id: 'y', min: 15),
    ]);
    expect(canMergeWatch([app.watchDataById('x')!, app.watchDataById('y')!]), contains('samme dag'));
    app.mergeWatch(['x', 'y']);
    expect(app.watchLog.any((d) => d.isMerged), isFalse);
  });

  test('sammenslåing beholder økt krysset av for hånd', () {
    app.markDone(lang);
    app.importFromWatch([
      gaatur(DateTime(2026, 12, 9, 10), id: 'h1', min: 25),
      gaatur(DateTime(2026, 12, 9, 11), id: 'h2', min: 25),
    ]);
    app.mergeWatch(['h1', 'h2']);
    expect(lang.status, SessionStatus.fullfort);
    expect(app.watchDataById(lang.watchId)!.isMerged, isTrue);
    expect(extras(), isEmpty);
  });

  test('distanse fra to kilder telles ikke dobbelt, og målinger over kanten deles', () {
    final a = DateTime(2026, 12, 9, 10), b = DateTime(2026, 12, 9, 11);
    const sh = 'com.sec.android.app.shealth', tlf = 'com.android.healthconnect.phone';
    final pts = <Delta>[
      for (var m = 0; m < 60; m += 10) (a.add(Duration(minutes: m)), a.add(Duration(minutes: m + 10)), 1000.0, sh),
      for (var m = 0; m < 60; m += 10) (a.add(Duration(minutes: m)), a.add(Duration(minutes: m + 10)), 950.0, tlf),
      // Går 5 min over slutten: halvparten tas med
      (b.subtract(const Duration(minutes: 5)), b.add(const Duration(minutes: 5)), 200.0, sh),
    ];
    expect(sumOneSource(pts, a, b, prefer: sh), 6100);
    expect(sumOneSource(pts, a, b, prefer: 'ukjent'), 6100); // kilden med mest
    expect(sumOneSource(pts.where((p) => p.$4 == tlf).toList(), a, b, prefer: sh), 5700);
    expect(sumOneSource(const [], a, b), isNull);
  });

  test('overlappende klokkeøkter telles bare én gang ved sammenslåing', () {
    // Automatisk oppdaget tur 10:00–11:00 og samme tur startet på klokka 10:10–10:50, pluss 12:00–12:20
    app.importFromWatch([
      gaatur(DateTime(2026, 12, 9, 10), id: 'auto', min: 60),
      gaatur(DateTime(2026, 12, 9, 10, 10), id: 'manuell', min: 40),
      gaatur(DateTime(2026, 12, 9, 12), id: 'kveld', min: 20),
    ]);
    app.mergeWatch(['auto', 'manuell', 'kveld']);
    final m = app.watchLog.firstWhere((d) => d.isMerged);
    expect(m.durationSec, 80 * 60);
    expect(m.distanceM, 12000); // 6 km + 0 (dekket) + 6 km
    expect(m.zoneSec.reduce((x, y) => x + y), 80 * 60);
  });
}
