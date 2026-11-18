import 'package:flutter/material.dart';

import '../health_sync.dart';
import '../main.dart';
import 'plan_screen.dart';
import 'profile_screen.dart';
import 'progress_screen.dart';
import 'session_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _watchSync());
  }

  /// Hent nye økter fra klokka i bakgrunnen og si fra hvis noe ble lagt inn.
  Future<void> _watchSync() async {
    if (!mounted) return;
    final r = await HealthSync.instance.autoSync(AppScope.of(context));
    if (!mounted || r == null || r.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.summary), duration: const Duration(seconds: 5)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Ny dag siden sist? Oppdater stått-over-økter.
    if (s == AppLifecycleState.resumed) {
      final app = AppScope.of(context);
      app.refreshMissed();
      app.save();
      setState(() {});
      _watchSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final next = app.todaysOrNext;
    final pages = [
      PlanScreen(onOpenToday: () => setState(() => _tab = 1)),
      next == null
          ? const Scaffold(body: Center(child: Text('Ingen flere økter i planen. Godt jobbet!')))
          : SessionScreen(session: next, embedded: true),
      const ProgressScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Plan'),
          NavigationDestination(icon: Icon(Icons.fitness_center_outlined), selectedIcon: Icon(Icons.fitness_center), label: 'Økt'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Fremgang'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}
