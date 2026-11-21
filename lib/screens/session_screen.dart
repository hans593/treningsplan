import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../exercises.dart';
import '../main.dart';
import '../models.dart';
import '../move.dart';
import '../widgets.dart';
import 'extra_session_screen.dart';
import 'guided_screen.dart';
import 'watch_details.dart';
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
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.primary, letterSpacing: 0.4)),
        const SizedBox(height: 4),
        Text(s.title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.15)),
        if (s.note != null) ...[
          const SizedBox(height: 4),
          Text(s.note!, style: const TextStyle(color: muted, fontSize: 15)),
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
        if (app.watchDataById(s.watchId) case final wd?) ...[
          WatchDetailsCard(wd, planned: s.extra ? null : s, hrUnreliable: app.profile?.hrUnreliable ?? false),
          const SizedBox(height: 14),
        ],
        if (isStrength) ...[
          const Text('Varm opp 5–8 min først. Kontrollerte bevegelser – ingen hopp eller raske løft.',
              style: TextStyle(color: muted)),
          const SizedBox(height: 12),
          for (final orig in baseExercisesFor(s)) ...[
            Builder(builder: (context) {
              final id = resolveExercise(orig, profile: app.profile, swaps: app.exerciseSwaps);
              final last = s.exLog[id] ?? app.lastLogFor(id);
              return _ExerciseRow(
                id: id,
                original: orig,
                detail: s.type == SessionType.styrkeA ? repsFor(id, s) : '${s.workSec} sek',
                last: last?.label,
              );
            }),
            const SizedBox(height: 8),
          ],
          if (app.profile?.isSenior ?? false) ...[
            const _ExerciseRow(id: 'balanse', original: 'balanse', detail: '2 × 30 sek per bein til slutt'),
            const SizedBox(height: 8),
          ],
          const Text('Trykk på en øvelse for å se hvordan den gjøres, eller bytte den ut (f.eks. ved vondt kne). '
              'Velg vekter som gir 2–3 repetisjoner i reserve.',
              style: TextStyle(color: muted, fontSize: 14)),
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
                style: TextStyle(color: warnFg, fontSize: 14)),
          ),
        ],
        const SizedBox(height: 20),
        if (s.extra) ...[
          const Center(child: Text('✓ Ekstra økt utenom planen', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => editRegistration(context, s),
            icon: const Icon(Icons.edit),
            label: const Text('Endre registrering'),
          ),
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
              switch (s.resolution) {
                Resolution.forOppstart => 'Økta lå før du begynte å bruke appen.',
                Resolution.pause => 'Fravær – økta teller ikke som tapt.',
                Resolution.utlopt => 'Ikke gjennomført ${fmtDato(s.date)}, og for gammel til å tas igjen.',
                _ => s.resolved
                    ? 'Ikke gjennomført ${fmtDato(s.date)}. ${s.note ?? ''}'
                    : 'Ikke gjennomført innen ${fmtDato(s.date)}, og derfor regnet som ikke utført.',
              },
              style: const TextStyle(fontSize: 15, height: 1.4),
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
          if (s.canUndoCompensation) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.undo),
              onPressed: () async {
                final ok = await _confirm(context, 'Angre valget?',
                    'Det du valgte for denne tapte økta (${s.note?.toLowerCase() ?? ''}) fjernes, og du kan velge på nytt.');
                if (!ok) return;
                final err = app.undoCompensationFor(s);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Valget er angret')));
                }
              },
              label: const Text('Angre valget'),
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
          if (isStrength) ...[
            FilledButton.icon(
              onPressed: () => logWeights(context, s),
              icon: const Icon(Icons.fitness_center),
              label: Text(s.exLog.isEmpty ? 'Registrer vekter' : 'Endre vekter'),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: () => editRegistration(context, s),
            icon: const Icon(Icons.edit),
            label: const Text('Endre registrering'),
          ),
          TextButton(onPressed: () => app.markNotDone(s), child: const Text('Angre avkryssing')),
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
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: app.moveOptionsFor(s).isEmpty ? null : () => moveSheet(context, s),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Flytt dag'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: s.ease != null ? null : () => easeSheet(context, s),
                icon: const Icon(Icons.spa_outlined),
                label: Text(s.ease != null ? 'Gjort lettere' : 'Lettere i dag'),
              ),
            ),
          ]),
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
  final String original;
  final String detail;
  final String? last;
  const _ExerciseRow({required this.id, required this.original, required this.detail, this.last});

  @override
  Widget build(BuildContext context) {
    final ex = exercises[id]!;
    final swapped = id != original;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showExerciseSheet(context, id, original: original),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ExerciseFigure(id),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ex.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('$detail · ${ex.muscles}', style: const TextStyle(fontSize: 14, color: muted)),
                if (swapped || last != null)
                  Text(
                    [if (swapped) 'Byttet fra ${exercises[original]!.name.toLowerCase()}', if (last != null) 'Sist: $last'].join(' · '),
                    style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.primary),
                  ),
              ]),
            ),
            const Icon(Icons.chevron_right, color: muted),
          ]),
        ),
      ),
    );
  }
}

/// Instruksjon for øvelsen, og mulighet til å bytte den ut i alle kommende økter.
void showExerciseSheet(BuildContext context, String id, {String? original}) {
  final app = AppScope.of(context);
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Builder(builder: (ctx) {
          final ex = exercises[id]!;
          final alts = original == null ? <String>[] : alternativesFor(original, profile: app.profile);
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: ExerciseFigure(id, size: 180)),
            const SizedBox(height: 16),
            Text(ex.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            Text(ex.muscles, style: const TextStyle(color: muted, fontSize: 15)),
            const SizedBox(height: 12),
            Text(ex.cue, style: const TextStyle(fontSize: 16, height: 1.45)),
            const SizedBox(height: 12),
            Text('Lettere variant: ${ex.easier}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            if (alts.length > 1) ...[
              const SizedBox(height: 20),
              const Text('Bytt øvelse', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Text('Gjelder alle kommende økter. Nyttig ved vondt kne, skulder eller rygg.',
                  style: TextStyle(color: muted, fontSize: 14)),
              const SizedBox(height: 8),
              for (final a in alts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ExerciseFigure(a, size: 48),
                  title: Text(exercises[a]!.name + (a == original ? ' (standard)' : '')),
                  subtitle: Text(exercises[a]!.muscles),
                  trailing: a == id ? const Icon(Icons.check_circle) : null,
                  onTap: () {
                    app.setExerciseSwap(original!, a);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${exercises[original]!.name} byttes med ${exercises[a]!.name.toLowerCase()}')));
                  },
                ),
            ],
          ]);
        }),
      ),
    ),
  );
}

/// Flytt eller bytt økta med en annen dag i samme uke.
Future<void> moveSheet(BuildContext context, Session s) async {
  final app = AppScope.of(context);
  final opts = app.moveOptionsFor(s);
  final chosen = await showModalBottomSheet<MoveOption>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
        Text('Flytt «${s.title}»', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        const Text('Samme uke. Ligger det en økt der fra før, bytter de dag.', style: TextStyle(color: muted, fontSize: 14)),
        const SizedBox(height: 8),
        for (final o in opts)
          ListTile(
            enabled: o.allowed,
            leading: Icon(o.swapWith != null ? Icons.swap_horiz : Icons.event_available),
            title: Text(fmtUkedag(o.date)),
            subtitle: Text(!o.allowed
                ? o.reason!
                : o.swapWith != null
                    ? 'Bytt med ${o.swapWith!.title[0].toLowerCase()}${o.swapWith!.title.substring(1)}'
                    : 'Ledig dag'),
            onTap: o.allowed ? () => Navigator.pop(ctx, o) : null,
          ),
      ]),
    ),
  );
  if (chosen == null) return;
  app.moveSession(s, chosen);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Flyttet til ${fmtUkedag(chosen.date).toLowerCase()}')));
  }
}

/// «Gjør lettere i dag»: kortere økt, eller bytt til rolig tur.
Future<void> easeSheet(BuildContext context, Session s) async {
  final app = AppScope.of(context);
  final e = await showModalBottomSheet<Ease>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Gjør lettere i dag', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const Text('Lite tid eller dårlig form? Det er alltid trygt å gjøre mindre.', style: TextStyle(color: muted, fontSize: 14)),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Kortere økt'),
            subtitle: Text(switch (s.type) {
              SessionType.styrkeA || SessionType.styrkeB => 'Én runde mindre',
              SessionType.motbakke => 'To drag mindre',
              _ => 'Omtrent en tredjedel kortere',
            }),
            onTap: () => Navigator.pop(ctx, Ease.kortere),
          ),
          if (s.type != SessionType.restitusjon)
            ListTile(
              leading: const Icon(Icons.directions_walk),
              title: const Text('Bytt til rolig tur'),
              subtitle: const Text('Inntil 30 minutter i rolig tempo'),
              onTap: () => Navigator.pop(ctx, Ease.rolig),
            ),
        ]),
      ),
    ),
  );
  if (e != null) app.easeSession(s, e);
}

/// Rett varighet, anstrengelse og følelse (og type for ekstraøkter).
Future<void> editRegistration(BuildContext context, Session s) async {
  final app = AppScope.of(context);
  var minutes = s.minutes;
  var effort = s.effort;
  var feeling = s.feeling;
  var kind = ExtraKind.values.where((k) => k.label == s.title).firstOrNull;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Endre registrering'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (s.extra) ...[
              const Text('Type', style: TextStyle(fontWeight: FontWeight.w600)),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final k in ExtraKind.values)
                  ChoiceChip(label: Text(k.label), selected: kind == k, onSelected: (_) => set(() => kind = k)),
              ]),
              const SizedBox(height: 12),
            ],
            Text('Varighet: $minutes min', style: const TextStyle(fontWeight: FontWeight.w600)),
            Slider(value: minutes.toDouble(), min: 5, max: 180, divisions: 35, onChanged: (v) => set(() => minutes = v.round())),
            const Text('Hvor hardt', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<Effort>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: Effort.lett, label: Text('Rolig')),
                ButtonSegment(value: Effort.moderat, label: Text('Middels')),
                ButtonSegment(value: Effort.hard, label: Text('Hardt')),
              ],
              selected: {effort},
              onSelectionChanged: (x) => set(() => effort = x.first),
            ),
            if (!s.extra) ...[
              const SizedBox(height: 12),
              const Text('Hvordan kjentes den?', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SegmentedButton<Feeling>(
                showSelectedIcon: false,
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment(value: Feeling.forLett, label: Text('Lett')),
                  ButtonSegment(value: Feeling.passe, label: Text('Passe')),
                  ButtonSegment(value: Feeling.forTungt, label: Text('Tung')),
                ],
                selected: {if (feeling != null) feeling!},
                onSelectionChanged: (x) => set(() => feeling = x.firstOrNull),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Avbryt')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Lagre')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  app.editSession(
    s,
    minutes: minutes,
    effort: effort,
    feeling: feeling,
    clearFeeling: feeling == null,
    type: kind?.type,
    title: kind?.label,
  );
}

/// Registrer vekt og repetisjoner per øvelse (styrke).
Future<void> logWeights(BuildContext context, Session s) async {
  final app = AppScope.of(context);
  final ids = exercisesFor(s, profile: app.profile, swaps: app.exerciseSwaps);
  final kg = <String, TextEditingController>{};
  final reps = <String, TextEditingController>{};
  for (final id in ids) {
    final l = s.exLog[id] ?? app.lastLogFor(id);
    kg[id] = TextEditingController(text: l?.kg == null ? '' : fmtKg(l!.kg!));
    reps[id] = TextEditingController(text: l?.reps?.toString() ?? '');
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Vekter og repetisjoner'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(shrinkWrap: true, children: [
          const Text('Tyngste sett. Forrige registrering er fylt inn.', style: TextStyle(color: muted, fontSize: 14)),
          for (final id in ids)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Expanded(flex: 5, child: Text(exercises[id]!.name, style: const TextStyle(fontSize: 15))),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: kg[id],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]'))],
                    decoration: const InputDecoration(labelText: 'kg', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: reps[id],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'rep', isDense: true),
                  ),
                ),
              ]),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Avbryt')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Lagre')),
      ],
    ),
  );
  if (ok != true) return;
  double? n(String t) {
    final v = double.tryParse(t.replaceAll(',', '.').trim());
    return v == null || v < 0 || v > 200 ? null : v;
  }
  app.logExercises(s, {
    for (final id in ids)
      id: ExLog(kg: n(kg[id]!.text), reps: int.tryParse(reps[id]!.text)?.clamp(1, 200)),
  });
}
