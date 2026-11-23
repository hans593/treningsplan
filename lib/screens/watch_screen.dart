import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';

import '../health_sync.dart';
import '../main.dart';
import '../watch_import.dart';
import '../widgets.dart';
import 'watch_details.dart';

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
  final Set<String> _sel = {};

  DateTime? get _selDay {
    if (_sel.isEmpty) return null;
    final d = AppScope.of(context).watchDataById(_sel.first);
    return d == null ? null : dateOnly(d.start);
  }

  Future<void> _merge() async {
    final app = AppScope.of(context);
    final items = [for (final id in _sel) app.watchDataById(id)].whereType<WatchData>().toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final err = canMergeWatch(items);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final total = items.fold<int>(0, (a, d) => a + d.durationSec);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Slå sammen ${items.length} økter?'),
        content: Text('${fmtUkedag(items.first.start)} kl. ${fmtKl(items.first.start)}–${fmtKl(items.last.end)}.\n\n'
            'Samlet tid i bevegelse: ${fmtVarighet(total)}. Puls vektes etter hvor lenge hver del varte, '
            'og distanse, skritt og tid i pulssoner legges sammen.\n\n'
            'Det delene har registrert hver for seg, fjernes. Den samlede økta krysser av planen hvis den passer, '
            'ellers blir den én ekstra økt. Du kan dele den opp igjen senere.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Avbryt')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Slå sammen')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = app.mergeWatch(_sel.toList());
    setState(() => _sel.clear());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.lines.isEmpty ? 'Slått sammen.' : 'Slått sammen. ${r.lines.join(' ')}'),
        duration: const Duration(seconds: 6)));
  }

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

  Future<void> _diagnose() async {
    setState(() => _busy = true);
    final app = AppScope.of(context);
    String text;
    try {
      text = await HealthSync.instance.diagnose(app);
    } catch (e) {
      text = 'Feilsøking feilet: $e';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Feilsøk'),
        content: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(fontSize: 13))),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            child: const Text('Kopier'),
          ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Lukk')),
        ],
      ),
    );
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
    final selDay = _selDay;
    final visible = app.watchLog.where((d) => d.mergedInto == null).take(40).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Samsung-klokke')),
      bottomNavigationBar: _sel.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: const BoxDecoration(
                    color: Colors.white, boxShadow: [BoxShadow(blurRadius: 8, color: Color(0x22000000))]),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text('${_sel.length} valgt', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(fmtVarighet(_sel.map((id) => app.watchDataById(id)?.durationSec ?? 0).fold(0, (a, b) => a + b)),
                          style: const TextStyle(fontSize: 14, color: muted)),
                    ]),
                  ),
                  TextButton(
                      style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                      onPressed: () => setState(_sel.clear),
                      child: const Text('Avbryt')),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: _sel.length >= 2 ? _merge : null,
                    icon: const Icon(Icons.merge_type),
                    label: const Text('Slå sammen'),
                  ),
                ]),
              ),
            ),
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
                            child: Text(n, style: TextStyle(fontSize: 13, color: cs.primary, fontWeight: FontWeight.w700))),
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
            TextButton.icon(
              onPressed: _busy ? null : _diagnose,
              icon: const Icon(Icons.bug_report_outlined),
              label: const Text('Feilsøk: hva finnes i Health Connect?'),
            ),
            const SizedBox(height: 8),
            Text(
              app.lastWatchSync == null ? 'Ikke hentet ennå' : 'Sist hentet ${fmtTid(app.lastWatchSync!)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 14),
            ),
          ],
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          for (final l in _lines)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('• $l', style: const TextStyle(fontSize: 14))),
          if (app.watchLog.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Økter fra klokka', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Trykk på en økt for tid, puls og pulssoner. Mange korte økter samme dag? '
                'Kryss av dem som hører sammen, og trykk «Slå sammen».',
                style: TextStyle(color: muted, fontSize: 14, height: 1.4)),
            const SizedBox(height: 8),
            for (var i = 0; i < visible.length; i++) ...[
              if (i == 0 || dateOnly(visible[i].start) != dateOnly(visible[i - 1].start))
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                  child: Text(fmtUkedag(visible[i].start),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: muted)),
                ),
              WatchLogTile(
                visible[i],
                onTap: () => openWatchDetails(context, visible[i]),
                selected: _sel.contains(visible[i].id),
                onSelect: selDay != null && dateOnly(visible[i].start) != selDay
                    ? null
                    : (v) => setState(() => v ? _sel.add(visible[i].id) : _sel.remove(visible[i].id)),
              ),
            ],
          ],
          const SizedBox(height: 16),
          _Info(app.profile?.hrUnreliable ?? false
              ? 'Du har oppgitt at medisin påvirker pulsen, så anstrengelsen bedømmes ut fra aktiviteten og ikke pulsen.'
              : 'Anstrengelsen beregnes fra pulsen: under 64 % av makspuls er rolig, 64–77 % middels og over det hardt. '
                  'Makspuls: ${app.profile?.maxHr ?? (208 - 0.7 * (app.profile?.age ?? 60)).round()}'
                  '${app.profile?.maxHr != null ? ' (din egen)' : ' (anslått ut fra alder – kan endres under Profil → Juster)'}. '
                  'Er pulsen høy i perioder under en gå- eller løpetur, regnes økta som intervaller.'),
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
        child: Text(text, style: const TextStyle(fontSize: 14, height: 1.45)),
      );
}


void openWatchDetails(BuildContext context, WatchData d) {
  final app = AppScope.of(context);
  final s = app.weeks.expand((w) => w.sessions).where((x) => x.watchId == d.id).firstOrNull;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(d.activity)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          WatchDetailsCard(d, planned: s == null || s.extra ? null : s, hrUnreliable: app.profile?.hrUnreliable ?? false),
          if (d.isMerged) ...[
            const SizedBox(height: 16),
            const Text('Deler', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            for (final id in d.parts)
              if (app.watchDataById(id) case final part?)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.watch),
                  title: Text('kl. ${fmtKl(part.start)}–${fmtKl(part.end)} · ${fmtVarighet(part.durationSec)}'),
                  subtitle: Text([
                    part.activity,
                    if (part.avgHr != null) 'snittpuls ${part.avgHr}',
                  ].join(' · ')),
                ),
            const SizedBox(height: 8),
            Builder(
              builder: (ctx) => OutlinedButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: ctx,
                    builder: (c) => AlertDialog(
                      title: const Text('Dele opp igjen?'),
                      content: const Text('Delene legges inn hver for seg igjen. Korte deler under 10 min regnes ikke med i planen.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Avbryt')),
                        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Del opp')),
                      ],
                    ),
                  );
                  if (ok != true || !ctx.mounted) return;
                  app.splitWatch(d.id);
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.call_split),
                label: const Text('Del opp igjen'),
              ),
            ),
          ],
        ]),
      ),
    ),
  );
}
