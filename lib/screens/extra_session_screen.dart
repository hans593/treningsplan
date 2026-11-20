import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../widgets.dart';

/// Typer økter man kan registrere utenom planen.
enum ExtraKind {
  gange('Rask gange / tur', SessionType.langtur, Effort.lett, 45),
  jogging('Jogging / løping', SessionType.kondisjon, Effort.moderat, 30),
  intervaller('Intervaller / motbakker', SessionType.motbakke, Effort.hard, 40),
  styrke('Styrketrening', SessionType.styrkeA, Effort.moderat, 35),
  sykling('Sykling', SessionType.kondisjon, Effort.moderat, 45),
  ski('Langrenn / ski', SessionType.kondisjon, Effort.moderat, 60),
  annet('Annen aktivitet', SessionType.restitusjon, Effort.lett, 30);

  final String label;
  final SessionType type;
  final Effort effort;
  final int minutes;
  const ExtraKind(this.label, this.type, this.effort, this.minutes);
}

class ExtraSessionScreen extends StatefulWidget {
  final DateTime? initialDate;
  const ExtraSessionScreen({super.key, this.initialDate});

  @override
  State<ExtraSessionScreen> createState() => _ExtraSessionScreenState();
}

class _ExtraSessionScreenState extends State<ExtraSessionScreen> {
  late DateTime _date;
  ExtraKind _kind = ExtraKind.gange;
  int _minutes = ExtraKind.gange.minutes;
  Effort _effort = ExtraKind.gange.effort;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    final init = widget.initialDate ?? app.today;
    _date = init.isAfter(app.today) ? app.today : init;
  }

  Future<void> _pickDate() async {
    final app = AppScope.of(context);
    final first = app.weeks.first.monday.isBefore(app.profile!.startDate) ? app.profile!.startDate : app.weeks.first.monday;
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: first,
      lastDate: app.today,
      helpText: 'Når trente du?',
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    final app = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    // Var dette egentlig dagens planlagte økt?
    final planned = app.plannedMatch(_date, _kind.type);
    if (planned != null) {
      final isPlanned = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Var dette den planlagte økta?'),
          content: Text('Planen hadde «${planned.title}» ${fmtUkedag(_date).toLowerCase()}. '
              'Skal økta registreres som den, eller som en ekstra økt?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Ekstra økt')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Den planlagte')),
          ],
        ),
      );
      if (isPlanned == null) return;
      if (isPlanned) {
        if (planned.status == SessionStatus.staattOver) {
          app.backRegister(planned);
        } else {
          app.markDone(planned);
        }
        messenger.showSnackBar(SnackBar(content: Text('«${planned.title}» er registrert som gjennomført')));
        nav.pop();
        return;
      }
    }

    final covered = app.addExtra(
      date: _date,
      type: _kind.type,
      title: _kind.label,
      minutes: _minutes,
      effort: _effort,
    );
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      content: Text(covered.isEmpty
          ? 'Ekstra økt registrert. Den regnes med i ukas trening.'
          : 'Ekstra økt registrert. Den erstatter ${covered.map((s) => '«${s.title}» ${fmtDato(s.date)}').join(' og ')}.'),
    ));
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final missed = app.unresolvedMissed;
    return Scaffold(
      appBar: AppBar(title: const Text('Registrer økt')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Text('Økter du gjør utenom planen regnes med. Har du stått over en planlagt økt, '
              'kan en ekstra økt av samme slag ta den igjen.',
              style: TextStyle(color: muted, fontSize: 14, height: 1.4)),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event),
              title: const Text('Dato'),
              subtitle: Text(_date == app.today ? 'I dag, ${fmtDato(_date)}' : fmtUkedag(_date)),
              trailing: const Icon(Icons.edit_calendar),
              onTap: _pickDate,
            ),
          ),
          const SizedBox(height: 16),
          const Text('Hva trente du?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in ExtraKind.values)
              ChoiceChip(
                label: Text(k.label),
                selected: _kind == k,
                onSelected: (_) => setState(() {
                  _kind = k;
                  _minutes = k.minutes;
                  _effort = k.effort;
                }),
              ),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            const Expanded(child: Text('Varighet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            Text('$_minutes min', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
          Slider(
            value: _minutes.toDouble(),
            min: 10,
            max: 180,
            divisions: 34,
            label: '$_minutes min',
            onChanged: (v) => setState(() => _minutes = v.round()),
          ),
          const SizedBox(height: 8),
          const Text('Hvor hardt var det?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SegmentedButton<Effort>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: Effort.lett, label: Text('Rolig')),
              ButtonSegment(value: Effort.moderat, label: Text('Middels')),
              ButtonSegment(value: Effort.hard, label: Text('Hardt')),
            ],
            selected: {_effort},
            onSelectionChanged: (s) => setState(() => _effort = s.first),
          ),
          const SizedBox(height: 6),
          Text(
            switch (_effort) {
              Effort.lett => 'Anstrengelse 3–5 av 10: du kan snakke hele tiden.',
              Effort.moderat => 'Anstrengelse 5–7 av 10: litt andpusten.',
              Effort.hard => 'Anstrengelse 7–9 av 10: tydelig andpusten.',
            },
            style: const TextStyle(color: muted, fontSize: 14),
          ),
          if (missed.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: warnBg, borderRadius: BorderRadius.circular(12)),
              child: Text(
                'Ikke tatt igjen: ${missed.map((m) => '${m.title} ${fmtDato(m.date)} (${m.minutes} min)').join(', ')}. '
                'En ekstra økt av samme slag på minst 70 % av tiden, i samme uke eller inntil 7 dager etter, tar den igjen.',
                style: const TextStyle(color: warnFg, fontSize: 14, height: 1.4),
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Lagre økt')),
        ],
      ),
    );
  }
}
