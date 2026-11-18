import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../widgets.dart';
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
    final allMissed = app.unresolvedMissed;
    final missed = allMissed.length > 2 ? allMissed.sublist(allMissed.length - 2) : allMissed;
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
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.primary, letterSpacing: 0.5)),
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
                style: const TextStyle(fontSize: 13, color: muted)),
            const SizedBox(height: 14),
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
                          const Text('Se forslag til hvordan du tar den igjen →', style: TextStyle(color: warnFg)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
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
            const SizedBox(height: 8),
            Text(
              week.deload
                  ? 'Lettuke: mindre mengde gir kroppen tid til å bygge seg opp.'
                  : 'Dager uten økt er hvile eller valgfri rolig tur. Trener du ekstra, registrer det med knappen nederst.',
              style: const TextStyle(fontSize: 13, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
