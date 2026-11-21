import 'package:flutter/material.dart';

import '../health_sync.dart';
import '../main.dart';
import '../models.dart';
import '../widgets.dart';
import 'absence_screen.dart';
import 'extra_session_screen.dart';
import 'missed_screen.dart';
import 'session_screen.dart';

class PlanScreen extends StatefulWidget {
  final VoidCallback onOpenToday;
  const PlanScreen({super.key, required this.onOpenToday});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  int? _weekIndex;

  Future<void> _startToday(BuildContext context) async {
    final app = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Start planen i dag?'),
        content: Text('Planen bygges på nytt fra i dag, ${fmtDato(app.today)}, med samme mål og måldato. '
            'Den første uka blir kort, og planen starter rolig.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Avbryt')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Start i dag')),
        ],
      ),
    );
    if (ok != true) return;
    app.startToday();
    setState(() => _weekIndex = null);
    if (app.watchSync) {
      final r = await HealthSync.instance.autoSync(app, force: true);
      if (r != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.summary)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.weeks.isEmpty) return const SizedBox.shrink();
    final idx = (_weekIndex ?? app.currentWeek!.index).clamp(0, app.weeks.length - 1);
    final week = app.weeks[idx];
    final total = app.weeks.length;
    final planned = week.sessions.where((s) => !s.extra && s.resolution != Resolution.forOppstart).toList();
    final done = planned
        .where((s) => s.status == SessionStatus.fullfort || s.resolution == Resolution.ekstraOkt)
        .length;
    final extras = week.sessions.where((s) => s.extra).length;
    final suggestion = app.suggestedAbsence;
    final allMissed = suggestion == null ? app.unresolvedMissed : <Session>[];
    final missed = allMissed.length > 2 ? allMissed.sublist(allMissed.length - 2) : allMissed;
    final changes = app.unseenChanges;
    final absence = app.activeAbsence;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'registrer',
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExtraSessionScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Registrer økt'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          children: [
            Row(children: [
              IconButton(
                tooltip: 'Forrige uke',
                onPressed: idx > 0 ? () => setState(() => _weekIndex = idx - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Column(children: [
                  Text(week.phase.toUpperCase() + (week.deload && week.phase != 'Testuke' ? ' · LETTUKE' : ''),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.primary, letterSpacing: 0.5)),
                  Text('Uke ${idx + 1} av $total', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                  Text('${fmtDato(week.monday)} – ${fmtDato(week.sunday)}', style: const TextStyle(color: muted)),
                ]),
              ),
              IconButton(
                tooltip: 'Neste uke',
                onPressed: idx < total - 1 ? () => setState(() => _weekIndex = idx + 1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: planned.isEmpty ? 0 : done / planned.length,
                minHeight: 8,
                backgroundColor: const Color(0xFFDDE3DE),
              ),
            ),
            const SizedBox(height: 6),
            Text(
                '$done av ${planned.length} planlagte økter gjennomført'
                '${extras > 0 ? ' · $extras ekstra' : ''}',
                style: const TextStyle(fontSize: 14, color: muted)),
            const SizedBox(height: 14),
            if (app.notStarted) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Planen starter ${fmtDatoLang(app.profile!.startDate)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text('Vil du heller begynne nå? Målet og måldatoen beholdes, og økter du '
                      'har tatt på klokka i dag regnes med.', style: TextStyle(fontSize: 15, height: 1.35)),
                  const SizedBox(height: 10),
                  FilledButton(onPressed: () => _startToday(context), child: const Text('Start planen i dag')),
                ]),
              ),
              const SizedBox(height: 10),
            ],
            // Forklaring når planen er endret (lettere/tyngre, fravær, opptrapping)
            if (changes.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Planen er endret', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      for (final c in changes.reversed.take(3))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(c.reason, style: const TextStyle(fontSize: 15, height: 1.35)),
                        ),
                    ]),
                  ),
                  TextButton(onPressed: app.markChangesSeen, child: const Text('OK')),
                ]),
              ),
              const SizedBox(height: 10),
            ],
            // Har vært borte en stund: ett samlet forslag i stedet for mange varsler
            if (suggestion != null) ...[
              Material(
                color: warnBg,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => AbsenceScreen(from: suggestion.from, to: suggestion.to))),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      const Icon(Icons.healing, color: Color(0xFFB4501A)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Har du vært borte siden ${fmtDato(suggestion.from)}?',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          const Text('Registrer fravær, så tilpasses planen samlet →', style: TextStyle(color: warnFg, fontSize: 15)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (absence != null) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                decoration: BoxDecoration(color: const Color(0xFFEEF2EF), borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  const Icon(Icons.beach_access),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${absence.reason}: ${fmtDato(absence.from)}–${fmtDato(absence.to)}',
                        style: const TextStyle(fontSize: 15)),
                  ),
                  if (!absence.from.isAfter(app.today))
                    TextButton(
                      onPressed: () => app.endAbsenceNow(absence),
                      child: const Text('Tilbake nå'),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
            ],
            for (final m in missed) ...[
              Material(
                color: warnBg,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MissedScreen(missed: m))),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Color(0xFFB4501A)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Du sto over: ${m.title} (${ukedager[m.date.weekday - 1]})',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          const Text('Se forslag til hvordan du tar den igjen →', style: TextStyle(color: warnFg, fontSize: 15)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (allMissed.length > 2) ...[
              Text('… og ${allMissed.length - 2} til som ikke er tatt igjen. Trykk på økta i listen.',
                  style: const TextStyle(color: warnFg, fontSize: 14)),
              const SizedBox(height: 10),
            ],
            for (final s in week.sessions) ...[
              SessionTile(
                session: s,
                isToday: s.date == app.today && s.status == SessionStatus.planlagt,
                onTap: () {
                  if (s.date == app.today && s.status == SessionStatus.planlagt) {
                    widget.onOpenToday();
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => SessionScreen(session: s)));
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
            if (week.sessions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Ingen økter denne uken.', textAlign: TextAlign.center),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AbsenceScreen())),
                icon: const Icon(Icons.event_busy),
                label: const Text('Syk, ferie eller skadet? Registrer fravær'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              week.deload
                  ? 'Lettuke: mindre mengde gir kroppen tid til å bygge seg opp.'
                  : 'Dager uten økt er hvile eller valgfri rolig tur. Trener du ekstra, registrer det med knappen nederst.',
              style: const TextStyle(fontSize: 14, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
