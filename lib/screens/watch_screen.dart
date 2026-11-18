import 'package:flutter/material.dart';

import '../health_sync.dart';
import '../main.dart';
import '../widgets.dart';

class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  WatchStatus? _status;
  bool _access = false;
  bool _busy = false;
  List<String> _lines = [];
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await HealthSync.instance.status();
    final a = s == WatchStatus.klar && await HealthSync.instance.hasAccess();
    if (!mounted) return;
    setState(() {
      _status = s;
      _access = a;
    });
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    final app = AppScope.of(context);
    try {
      final ok = await HealthSync.instance.connect();
      if (ok) {
        app.setWatchSync(true);
        await _syncNow();
      } else {
        _message = 'Fikk ikke tilgang. Prøv igjen, og huk av for Trening, Puls og Vekt.';
      }
    } catch (e) {
      _message = 'Noe gikk galt: $e';
    }
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    final app = AppScope.of(context);
    try {
      final r = await HealthSync.instance.sync(app);
      _lines = r.lines;
      _message = r.summary;
    } catch (e) {
      _message = 'Kunne ikke hente fra Health Connect: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Samsung-klokke')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Text(
            'Økter du tar på klokka, hentes automatisk når du åpner appen. '
            'En økt samme dag og av samme slag som den planlagte krysser av den planlagte. '
            'Andre økter registreres som ekstra, og kan ta igjen tapte økter.',
            style: TextStyle(color: muted, fontSize: 14, height: 1.45),
          ),
          const SizedBox(height: 16),
          if (_status == null)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (_status == WatchStatus.ikkeStottet)
            const _Info('Klokke-synk virker bare på Android-telefoner med Health Connect. '
                'Galaxy Watch kan ikke kobles til iPhone.')
          else if (_status == WatchStatus.maaInstalleres || _status == WatchStatus.maaOppdateres) ...[
            _Info(_status == WatchStatus.maaInstalleres
                ? 'Health Connect er ikke installert. Den er innebygd fra Android 14, ellers lastes den ned fra Google Play.'
                : 'Health Connect må oppdateres i Google Play.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                await HealthSync.instance.installHealthConnect();
              },
              child: Text(_status == WatchStatus.maaInstalleres ? 'Installer Health Connect' : 'Oppdater Health Connect'),
            ),
            TextButton(onPressed: _refresh, child: const Text('Sjekk igjen')),
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Slik setter du det opp', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  for (final (n, t) in [
                    ('1', 'Åpne Samsung Health på telefonen.'),
                    ('2', 'Gå til menyen (☰ eller ⋮) → Innstillinger → Health Connect.'),
                    ('3', 'Gi Samsung Health lov til å dele Trening, Puls og Vekt.'),
                    ('4', 'Trykk «Koble til» her, og tillat Treningsplan å lese de samme dataene.'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        CircleAvatar(
                            radius: 12,
                            backgroundColor: cs.primaryContainer,
                            child: Text(n, style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w700))),
                        const SizedBox(width: 10),
                        Expanded(child: Text(t, style: const TextStyle(fontSize: 15, height: 1.35))),
                      ]),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            if (!_access)
              FilledButton(onPressed: _busy ? null : _connect, child: const Text('Koble til'))
            else ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hent økter automatisk'),
                subtitle: const Text('Når appen åpnes'),
                value: app.watchSync,
                onChanged: app.setWatchSync,
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _syncNow,
                icon: const Icon(Icons.sync),
                label: const Text('Hent nå'),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              app.lastWatchSync == null ? 'Ikke hentet ennå' : 'Sist hentet ${fmtTid(app.lastWatchSync!)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 13),
            ),
          ],
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          for (final l in _lines)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('• $l', style: const TextStyle(fontSize: 14))),
          const SizedBox(height: 16),
          const _Info('Anstrengelsen beregnes fra pulsen: under 64 % av makspuls er rolig, 64–77 % middels og over det hardt. '
              'Makspulsen anslås ut fra alderen din. Er pulsen høy i perioder under en gå- eller løpetur, regnes økta som intervaller.'),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final String text;
  const _Info(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFEEF2EF), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(fontSize: 13, height: 1.45)),
      );
}
