import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treningsplan/main.dart';
import 'package:treningsplan/models.dart';
import 'package:treningsplan/state.dart';

import 'plan_test.dart' show hansProfil;

void main() {
  testWidgets('Oppsett vises ved første start', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState();
    await app.load();
    await tester.pumpWidget(TreningsplanApp(state: app));
    await tester.pumpAndSettle();
    expect(find.text('Lag din plan'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Lag treningsplan'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Lag treningsplan'), findsOneWidget);
  });

  testWidgets('Ukeplan, økt med illustrasjoner og fremgang', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var now = DateTime(2026, 12, 1);
    final app = AppState(clock: () => now);
    await app.load();
    app.createPlan(hansProfil());
    now = DateTime(2026, 12, 17);
    app.refreshMissed();
    await tester.pumpWidget(TreningsplanApp(state: app));
    await tester.pumpAndSettle();
    expect(find.text('Uke 3 av 22'), findsOneWidget);
    expect(find.textContaining('Har du vært borte'), findsOneWidget);

    // Dagens økt (torsdag = Styrke B)
    await tester.tap(find.text('Økt'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Styrke B'), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Illustrasjon')), findsWidgets);

    await tester.tap(find.text('Fremgang').last);
    await tester.pumpAndSettle();
    expect(find.text('Vekt mot mål'), findsOneWidget);

    expect(app.weeks[2].sessions.any((s) => s.status == SessionStatus.staattOver), isTrue);
  });
}
