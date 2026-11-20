import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../state.dart' show absenceSteps;
import '../widgets.dart';

/// Registrer fravær: sykdom, ferie eller skade – bakover eller frem i tid.
class AbsenceScreen extends StatefulWidget {
  final DateTime? from;
  final DateTime? to;
  const AbsenceScreen({super.key, this.from, this.to});

  @override
  State<AbsenceScreen> createState() => _AbsenceScreenState();
}

class _AbsenceScreenState extends State<AbsenceScreen> {
  late DateTime _from, _to;
  String _reason = 'Sykdom';
  bool _shift = false;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final today = AppScope.of(context).today;
    _from = widget.from ?? today;
    _to = widget.to ?? today.add(const Duration(days: 6));
  }

  Future<void> _pick(bool from) async {
    final app = AppScope.of(context);
    final p = app.profile!;
    final d = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: from ? p.startDate : _from,
      lastDate: p.endDate,
      helpText: from ? 'Første dag borte' : 'Siste dag borte',
    );
    if (d == null) return;
    setState(() {
      if (from) {
        _from = d;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = d;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final days = _to.difference(_from).inDays + 1;
    final steps = absenceSteps(days);
    final weeksShift = (days / 7).ceil();
    return Scaffold(
      appBar: AppBar(title: const Text('Fravær')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Text(
            'Syk, på ferie eller skadet? Økter i perioden regnes ikke som tapt. '
            'Etter en uke eller mer starter planen med en lettere uke og bygger seg opp igjen.',
            style: TextStyle(color: muted, fontSize: 15, height: 1.45),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'Sykdom', label: Text('Syk')),
              ButtonSegment(value: 'Ferie', label: Text('Ferie')),
              ButtonSegment(value: 'Skade', label: Text('Skade')),
              ButtonSegment(value: 'Annet', label: Text('Annet')),
            ],
            selected: {_reason},
            onSelectionChanged: (s) => setState(() => _reason = s.first),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => _pick(true), child: Text('Fra ${fmtDato(_from)}'))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton(onPressed: () => _pick(false), child: Text('Til ${fmtDato(_to)}'))),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Text(
              '$days ${days == 1 ? 'dag' : 'dager'}. ${switch (steps) {
                0 => 'Planen fortsetter som før etterpå.',
                99 => 'Planen starter fra tilvenning igjen etterpå, med en lettere første uke.',
                _ => 'Etterpå blir det en lettere uke, og planen settes $steps ${steps == 1 ? 'steg' : 'steg'} ned før den bygger seg opp igjen.',
              }}',
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _shift,
            onChanged: (v) => setState(() => _shift = v ?? false),
            title: Text('Flytt måldatoen $weeksShift ${weeksShift == 1 ? 'uke' : 'uker'} frem'),
            subtitle: Text('Ny måldato: ${fmtDatoLang(app.profile!.endDate.add(Duration(days: 7 * weeksShift)))}'),
          ),
          if (_reason == 'Skade')
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Ved skade: start forsiktig og bytt øvelser som gjør vondt (trykk på øvelsen i økta).',
                  style: TextStyle(color: warnFg, fontSize: 14)),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              app.registerAbsence(_from, _to, _reason, shiftEndDate: _shift);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fraværet er registrert, og planen er tilpasset')));
            },
            child: const Text('Registrer fravær'),
          ),
        ],
      ),
    );
  }
}
