import 'package:flutter/material.dart';

import '../exercises.dart';
import '../main.dart';
import '../models.dart';
import '../widgets.dart';
import 'extra_session_screen.dart';
import 'guided_screen.dart';
import 'missed_screen.dart';

class SessionScreen extends StatelessWidget {
  final Session session;
  final bool embedded;
  const SessionScreen({super.key, required this.session, this.embedded = false});

  String _kicker(Session s) => s.extra ? 'Utenom planen' : switch (s.type) {
        SessionType.motbakke => 'Utendørs · kondisjon og puls',
        SessionType.styrkeA => 'Hjemme · kontrollert styrke',
        SessionType.styrkeB => 'Hjemme · CrossFit-inspirert sirkel',
        SessionType.langtur => 'Utendørs · rolig utholdenhet',
        SessionType.kondisjon => 'Utendørs · variert kondisjon',
        SessionType.restitusjon => 'Restitusjon',
      };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = session;
    final cs = Theme.of(context).colorScheme;
    final isStrength = !s.extra && (s.type == SessionType.styrkeA || s.type == SessionType.styrkeB);
    final missed = s.status == SessionStatus.staattOver;
    final done = s.status == SessionStatus.fullfort;

    final body = ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text('${fmtUkedag(s.date).toUpperCase()} · ${_kicker(s).toUpperCase()}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary, letterSpacing: 0.4)),
        const SizedBox(height: 4),
        Text(s.title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.15)),
        if (s.note != null) ...[
          const SizedBox(height: 4),
          Text(s.note!, style: const TextStyle(color: muted)),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: StatBox('Varighet', 'ca. ${s.minutes} min')),
          const SizedBox(width: 8),
          if (s.extra)
            Expanded(child: StatBox('Anstrengelse', effortLabel(s.effort)))
          else if (s.type == SessionType.motbakke) ...[
            Expanded(child: StatBox('Drag', '${s.reps} × ${fmtSek(s.workSec)}')),
            const SizedBox(width: 8),
            Expanded(child: StatBox('Pause', fmtSek(s.restSec))),
          ] else if (isStrength) ...[
            Expanded(child: StatBox('Runder', '${s.rounds}')),
            const SizedBox(width: 8),
            Expanded(
                child: StatBox(
                    s.type == SessionType.styrkeB ? 'Arbeid / pause' : 'Pause',
                    s.type == SessionType.styrkeB ? '${s.workSec} / ${s.restSec} s' : '60–90 s')),
          ] else
            Expanded(
                child: StatBox(
                    'Anstrengelse',
                    switch (s.type) {
                      SessionType.kondisjon => '4–6 av 10',
                      SessionType.langtur => '5–6 av 10',
                      _ => '3–4 av 10',
                    })),
        ]),
        const SizedBox(height: 14),
        if (isStrength) ...[
          const Text('Varm opp 5–8 min først. Kontrollerte bevegelser – ingen hopp eller raske løft.',
              style: TextStyle(color: muted)),
          const SizedBox(height: 12),
          for (final id in exercisesFor(s)) ...[
            _ExerciseRow(id: id, detail: s.type == SessionType.styrkeA ? repsFor(id, s) : '${s.workSec} sek'),
            const SizedBox(height: 8),
          ],
          if (app.profile?.isSenior ?? false) ...[
            const _ExerciseRow(id: 'balanse', detail: '2 × 30 sek per bein til slutt'),
            const SizedBox(height: 8),
          ],
          const Text('Velg vekter som gir 2–3 repetisjoner i reserve. Blir manualene for lette: '
              'flere repetisjoner, saktere tempo eller ett bein om gangen.',
              style: TextStyle(color: muted, fontSize: 13)),
        ] else if (!s.extra)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                switch (s.type) {
                  SessionType.motbakke =>
                    '10 min rask gange som oppvarming. Deretter ${s.reps} drag à ${fmtSek(s.workSec)} opp en bakke – '
                        'rask gange eller lett løping, tydelig andpusten men ikke maks. Gå rolig ned i ${fmtSek(s.restSec)} '
                        'mellom dragene. Avslutt med 15 min rask gange og 5 min nedtrapping.',
                  SessionType.langtur =>
                    'Rask gange i variert terreng i ${s.minutes} minutter, i et tempo der du fortsatt kan snakke.',
                  SessionType.kondisjon =>
                    'Veksle mellom jogging og rask gange i ${s.minutes} minutter. Du trenger ikke jogge hele tiden.',
                  _ => 'Rolig gåtur og lett tøying i ${s.minutes} minutter.',
                },
                style: const TextStyle(fontSize: 15, height: 1.45),
              ),
            ),
          ),
        if (!s.extra && (s.type == SessionType.motbakke || s.type == SessionType.kondisjon)) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: warnBg, borderRadius: BorderRadius.circular(10)),
            child: const Text('Stopp ved brystsmerter, svimmelhet eller uvanlig tung pust. '
                'Vondt i kne, hofte eller akilles? Bytt jogging med rask gange.',
                style: TextStyle(color: warnFg, fontSize: 13)),
          ),
        ],
        const SizedBox(height: 20),
        if (s.extra) ...[
          const Center(child: Text('✓ Ekstra økt utenom planen', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () async {
              final ok = await _confirm(context, 'Slette ekstra økt?',
                  s.covers != null ? 'Den tapte økta den erstattet blir stående som ikke tatt igjen.' : 'Økta fjernes fra planen.');
              if (ok) {
                app.deleteExtra(s);
                if (context.mounted && !embedded) Navigator.pop(context);
              }
            },
            child: const Text('Slett ekstra økt'),
          ),
        ] else if (missed) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFEEF2EF), borderRadius: BorderRadius.circular(12)),
            child: Text(
              s.resolution == Resolution.forOppstart
                  ? 'Økta lå før du begynte å bruke appen.'
                  : s.resolved
                      ? 'Ikke gjennomført ${fmtDato(s.date)}. ${s.note ?? ''}'
                      : 'Ikke gjennomført innen ${fmtDato(s.date)}, og derfor regnet som ikke utført.',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
          const SizedBox(height: 12),
          if (!s.resolved) ...[
            FilledButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MissedScreen(missed: s))),
              child: const Text('Ta igjen økta'),
            ),
            const SizedBox(height: 8),
          ],
          if (s.canBackRegister) ...[
            OutlinedButton(
              onPressed: () async {
                final ok = await _confirm(
                  context,
                  'Gjennomført ${fmtUkedag(s.date).toLowerCase()}?',
                  'Etterregistrer bare hvis du faktisk gjorde økta ${fmtDato(s.date)} og glemte å krysse av. '
                      'Trente du en annen dag, registrer den som ekstra økt – da regnes den med der.',
                );
                if (ok) app.backRegister(s);
              },
              child: Text('Jeg gjorde den ${fmtDato(s.date)} – etterregistrer'),
            ),
            const SizedBox(height: 8),
          ],
          TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExtraSessionScreen())),
            child: const Text('Trente en annen dag? Registrer ekstra økt'),
          ),
        ] else if (done) ...[
          Center(
              child: Text(s.note == 'Etterregistrert' ? '✓ Gjennomført (etterregistrert)' : '✓ Gjennomført',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          const SizedBox(height: 8),
          TextButton(onPressed: () => app.markNotDone(s), child: const Text('Angre')),
        ] else ...[
          FilledButton(
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => GuidedScreen(session: s))),
            child: const Text('Start økt'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              final f = await askFeeling(context);
              if (f != null) app.markDone(s, feeling: f);
            },
            child: const Text('Marker som gjennomført'),
          ),
        ],
      ],
    );

    if (embedded) return Scaffold(body: SafeArea(child: body));
    return Scaffold(appBar: AppBar(), body: body);
  }
}

Future<bool> _confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Avbryt')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ja')),
        ],
      ),
    ) ??
    false;

class _ExerciseRow extends StatelessWidget {
  final String id;
  final String detail;
  const _ExerciseRow({required this.id, required this.detail});

  @override
  Widget build(BuildContext context) {
    final ex = exercises[id]!;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showExerciseSheet(context, id),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ExerciseFigure(id),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ex.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('$detail · ${ex.muscles}', style: const TextStyle(fontSize: 13, color: muted)),
              ]),
            ),
            const Icon(Icons.info_outline, color: muted),
          ]),
        ),
      ),
    );
  }
}

void showExerciseSheet(BuildContext context, String id) {
  final ex = exercises[id]!;
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: ExerciseFigure(id, size: 200)),
          const SizedBox(height: 16),
          Text(ex.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          Text(ex.muscles, style: const TextStyle(color: muted)),
          const SizedBox(height: 12),
          Text(ex.cue, style: const TextStyle(fontSize: 16, height: 1.45)),
          const SizedBox(height: 12),
          Text('Lettere variant: ${ex.easier}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
      ),
    ),
  );
}
