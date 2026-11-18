import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'cloud_sync.dart';
import 'screens/home.dart';
import 'screens/onboarding.dart';
import 'state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  state.load().then((_) => CloudSync.instance.init(state));
  runApp(TreningsplanApp(state: state));
}

/// Gir alle skjermer tilgang til app-tilstanden.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

const brandGreen = Color(0xFF1F5C43);
const brandOrange = Color(0xFFC2581B);

ThemeData buildTheme() {
  final cs = ColorScheme.fromSeed(
    seedColor: brandGreen,
    primary: brandGreen,
    surface: const Color(0xFFF3F5F1),
  ).copyWith(primaryContainer: const Color(0xFFE3EEE7), onPrimaryContainer: brandGreen);
  return ThemeData(
    colorScheme: cs,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF3F5F1),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFDDE3DE)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

class TreningsplanApp extends StatelessWidget {
  final AppState state;
  const TreningsplanApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Treningsplan',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('nb'),
        supportedLocales: const [Locale('nb'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (app.profile == null) return const OnboardingScreen();
    return const HomeScreen();
  }
}
