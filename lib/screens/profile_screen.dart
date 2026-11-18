import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../widgets.dart';
import '../cloud_sync.dart';
import 'cloud_screen.dart';
import 'onboarding.dart';
import 'watch_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.profile!;
    String fitness() => switch (p.fitness) {
          Fitness.liteAktiv => 'Lite aktiv',
          Fitness.gaarRaskt => 'Går raskt 60 min',
          Fitness.kanJogge => 'Jogger 20–30 min',
          Fitness.trenerJevnlig => 'Trener jevnlig',
        };
    final rows = <(String, String)>[
      ('Alder', '${p.age} år'),
      ('Høyde', '${p.heightCm} cm'),
      ('Startvekt', '${fmtKg(p.weightKg)} kg'),
      ('Målvekt', '${fmtKg(p.targetKg)} kg'),
      ('Periode', '${fmtDatoLang(p.startDate)} – ${fmtDatoLang(p.endDate)}'),
      ('Lengde', '${p.totalWeeks} uker'),
      ('Form', fitness()),
      ('Intensitet', p.intensity.name[0].toUpperCase() + p.intensity.name.substring(1)),
      ('Treningsdager', '${p.daysPerWeek} per uke, ca. ${p.minutesPerSession} min'),
    ];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            const Text('Profil og plan', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(children: [
                  for (final (k, v) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        Expanded(child: Text(k, style: const TextStyle(color: muted))),
                        Flexible(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
                      ]),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.watch),
                title: const Text('Samsung-klokke'),
                subtitle: Text(app.watchSync
                    ? (app.lastWatchSync == null ? 'Koblet til' : 'Henter automatisk · sist ${fmtDato(app.lastWatchSync!)}')
                    : 'Hent økter automatisk fra klokka'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WatchScreen())),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListenableBuilder(
                listenable: CloudSync.instance,
                builder: (context, _) {
                  final u = CloudSync.instance.user;
                  return ListTile(
                    leading: Icon(u == null ? Icons.cloud_off : Icons.cloud_done),
                    title: const Text('Lagring i skyen'),
                    subtitle: Text(u == null ? 'Lag konto for å ta vare på dataene' : 'Logget inn som ${u.email}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CloudScreen())),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => OnboardingScreen(initial: p))),
              child: const Text('Juster mål og plan'),
            ),
            const SizedBox(height: 6),
            const Text('Endre målvekt, måldato, intensitet eller treningsmengde. Det du har gjort, beholdes.',
                textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () async {
                var keep = true;
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => StatefulBuilder(
                    builder: (c, setD) => AlertDialog(
                      title: const Text('Starte helt på nytt?'),
                      content: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('Planen og alle registrerte økter slettes, og du lager en ny plan fra start.'),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: keep,
                          onChanged: (v) => setD(() => keep = v ?? true),
                          title: const Text('Behold vektmålinger og tester'),
                        ),
                      ]),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Avbryt')),
                        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Start på nytt')),
                      ],
                    ),
                  ),
                );
                if (ok == true) app.reset(keepHistory: keep);
              },
              child: const Text('Start helt på nytt'),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: warnBg, borderRadius: BorderRadius.circular(14)),
              child: const Text(
                'Bruk anstrengelsesskalaen 1–10: rolige turer 3–4, rask gange 5–6, intervaller 7–8. '
                'Du trenger ikke presse pulsen til maks. Stopp ved brystsmerter, svimmelhet eller uvanlig tung pust. '
                'Ved hjerte- eller lungesykdom: avklar harde intervaller med fastlegen.',
                style: TextStyle(color: warnFg, fontSize: 13, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
