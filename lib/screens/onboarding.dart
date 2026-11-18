import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models.dart';
import '../widgets.dart';
import 'cloud_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final Profile? initial;
  const OnboardingScreen({super.key, this.initial});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _age, _height, _weight, _target;
  late DateTime _start, _end;
  late Fitness _fitness;
  late Intensity _intensity;
  late int _days, _minutes;
  late Set<Activity> _activities;
  late bool _health;
  bool _inited = false;

  bool get _adjust => widget.initial != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    if (_adjust) {
      final latest = AppScope.of(context).latestWeight;
      if (latest != null) _weight.text = fmtKg(latest);
    }
  }

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    final now = DateTime.now();
    _age = TextEditingController(text: p?.age.toString() ?? '');
    _height = TextEditingController(text: p?.heightCm.toString() ?? '');
    _weight = TextEditingController(text: p == null ? '' : fmtKg(p.weightKg));
    _target = TextEditingController(text: p == null ? '' : fmtKg(p.targetKg));
    _start = p?.startDate ?? DateTime(now.year, now.month, now.day);
    _end = p?.endDate ?? _start.add(const Duration(days: 7 * 12));
    _fitness = p?.fitness ?? Fitness.gaarRaskt;
    _intensity = p?.intensity ?? Intensity.moderat;
    _days = p?.daysPerWeek ?? 4;
    _minutes = p?.minutesPerSession ?? 45;
    _activities = p?.activities.toSet() ?? {Activity.manualer, Activity.raskGange, Activity.motbakker};
    _health = p?.healthWarning ?? false;
  }

  double? _num(String s) => double.tryParse(s.replaceAll(',', '.').trim());

  String? _range(String? v, double lo, double hi, String unit) {
    final n = _num(v ?? '');
    if (n == null) return 'Fyll inn';
    if (n < lo || n > hi) return 'Mellom ${lo.round()} og ${hi.round()} $unit';
    return null;
  }

  Future<void> _pickDate(bool start) async {
    final first = _adjust ? AppScope.of(context).earliestNewEndDate : DateTime(2024);
    final d = await showDatePicker(
      context: context,
      initialDate: start ? _start : (_end.isBefore(first) ? first : _end),
      firstDate: first,
      lastDate: DateTime(2035),
      locale: const Locale('nb'),
    );
    if (d == null) return;
    setState(() {
      if (start) {
        _start = d;
        if (!_end.isAfter(_start)) _end = _start.add(const Duration(days: 28));
      } else {
        _end = d;
      }
    });
  }

  int get _weeks => ((_end.difference(_start).inDays + 1) / 7).ceil();

  /// Uker igjen fra i dag (ved justering) eller fra start.
  int get _weeksLeft {
    if (!_adjust) return _weeks;
    final today = AppScope.of(context).today;
    return ((_end.difference(today).inDays + 1) / 7).ceil().clamp(1, 104);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_weeks < 2) {
      _snack('Planen må vare minst to uker.');
      return;
    }
    if (_activities.isEmpty) {
      _snack('Velg minst én aktivitet.');
      return;
    }
    final p = Profile(
      age: _num(_age.text)!.round(),
      heightCm: _num(_height.text)!.round(),
      weightKg: _num(_weight.text)!,
      targetKg: _num(_target.text)!,
      startDate: _start,
      endDate: _end,
      fitness: _fitness,
      intensity: _intensity,
      daysPerWeek: _days,
      minutesPerSession: _minutes,
      activities: _activities,
      healthWarning: _health,
    );
    final perWeek = (p.weightKg - p.targetKg) / _weeksLeft;
    if (perWeek > p.weightKg * 0.01) {
      final ok = await _confirm('Vektmålet er raskt',
          'Målet krever ${fmtKg(perWeek)} kg per uke, mer enn ca. 1 % av kroppsvekten. '
              'Det er tryggere å velge en senere måldato eller en høyere målvekt. Vil du fortsette likevel?');
      if (!ok) return;
    }
    if (_health) {
      final ok = await _confirm('Snakk med legen først',
          'Ved hjerte- eller lungesykdom eller symptomer ved anstrengelse bør du avklare oppstarten med fastlegen '
              'før du starter med harde intervaller. Planen starter rolig uansett. Fortsette?');
      if (!ok) return;
    }
    if (!mounted) return;
    final app = AppScope.of(context);
    if (_adjust) {
      final latest = app.latestWeight;
      final changed = latest == null || (latest - p.weightKg).abs() >= 0.05;
      final from = app.firstAdjustableWeek;
      app.adjustPlan(p, currentWeightKg: changed ? p.weightKg : null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(from == 0 ? 'Planen er laget på nytt' : 'Planen er justert fra uke ${from + 1}')));
      Navigator.pop(context);
    } else {
      app.createPlan(p);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Endre')),
            FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(80, 44)),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Fortsett')),
          ],
        ),
      ) ??
      false;

  Widget _field(String label, TextEditingController c, double lo, double hi, String unit) => TextFormField(
        controller: c,
        decoration: InputDecoration(labelText: '$label ($unit)'),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]'))],
        validator: (v) => _range(v, lo, hi, unit),
      );

  Widget _section(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...children,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final w = _num(_weight.text), t = _num(_target.text);
    final perWeek = (w != null && t != null) ? (w - t) / _weeksLeft : null;
    final app = AppScope.of(context);
    final from = _adjust ? app.firstAdjustableWeek : 0;
    return Scaffold(
      appBar: _adjust ? AppBar(title: const Text('Juster mål og plan')) : null,
      body: SafeArea(
        child: Form(
          key: _form,
          onChanged: () => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.initial == null) ...[
                const Text('Lag din plan',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.15)),
                const SizedBox(height: 6),
                const Text('Svar på noen spørsmål, så bygger appen et program fra startdato til målet ditt.',
                    style: TextStyle(fontSize: 15, color: muted)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CloudScreen())),
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: const Text('Har du konto? Logg inn og hent planen din'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _section('Om deg', [
                Row(children: [
                  Expanded(child: _field('Alder', _age, 16, 95, 'år')),
                  const SizedBox(width: 12),
                  Expanded(child: _field('Høyde', _height, 120, 220, 'cm')),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _field(_adjust ? 'Vekt i dag' : 'Vekt nå', _weight, 35, 250, 'kg')),
                  const SizedBox(width: 12),
                  Expanded(child: _field('Målvekt', _target, 35, 250, 'kg')),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<Fitness>(
                  initialValue: _fitness,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Formen din i dag'),
                  items: const [
                    DropdownMenuItem(value: Fitness.liteAktiv, child: Text('Lite aktiv, må bygge meg opp')),
                    DropdownMenuItem(value: Fitness.gaarRaskt, child: Text('Kan gå raskt i 60 minutter')),
                    DropdownMenuItem(value: Fitness.kanJogge, child: Text('Kan jogge 20–30 minutter')),
                    DropdownMenuItem(value: Fitness.trenerJevnlig, child: Text('Trener jevnlig og hardt')),
                  ],
                  onChanged: (v) => setState(() => _fitness = v!),
                ),
              ]),
              const SizedBox(height: 12),
              _section('Periode', [
                Row(children: [
                  Expanded(
                      child: OutlinedButton(
                          onPressed: _adjust ? null : () => _pickDate(true),
                          child: Text('Start: ${fmtDato(_start)} ${_start.year}'))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: OutlinedButton(
                          onPressed: () => _pickDate(false), child: Text('Mål: ${fmtDato(_end)} ${_end.year}'))),
                ]),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    perWeek == null
                        ? '$_weeks uker'
                        : '$_weeks uker${_adjust ? ' ($_weeksLeft igjen)' : ''} · '
                            '${fmtKg(w! - t!)} kg ${_adjust ? 'igjen ' : ''}≈ ${perWeek.toStringAsFixed(2).replaceAll('.', ',')} kg per uke',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              _section('Intensitet', [
                SegmentedButton<Intensity>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: Intensity.rolig, label: Text('Rolig')),
                    ButtonSegment(value: Intensity.moderat, label: Text('Moderat')),
                    ButtonSegment(value: Intensity.krevende, label: Text('Krevende')),
                  ],
                  selected: {_intensity},
                  onSelectionChanged: (s) => setState(() => _intensity = s.first),
                ),
                const SizedBox(height: 8),
                Text(
                  switch (_intensity) {
                    Intensity.rolig => 'Korte intervaller, rolig økning. Godt valg for oppstart.',
                    Intensity.moderat => 'Intervaller på 7–8 av 10 i anstrengelse. Ingen maksimaløkter.',
                    Intensity.krevende => 'Lengre og flere intervaller og flere styrkerunder mot slutten.',
                  },
                  style: const TextStyle(color: muted, fontSize: 14),
                ),
              ]),
              const SizedBox(height: 12),
              _section('Hvor mye vil du trene?', [
                Row(children: [
                  const Expanded(child: Text('Treningsdager per uke', style: TextStyle(fontSize: 15))),
                  IconButton.outlined(
                    tooltip: 'Færre dager',
                    onPressed: _days > 3 ? () => setState(() => _days--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                      width: 32,
                      child: Text('$_days',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                  IconButton.outlined(
                    tooltip: 'Flere dager',
                    onPressed: _days < 6 ? () => setState(() => _days++) : null,
                    icon: const Icon(Icons.add),
                  ),
                ]),
                const SizedBox(height: 10),
                const Text('Vanlig lengde på en økt', style: TextStyle(fontSize: 15)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  for (final m in [30, 45, 60])
                    ChoiceChip(
                      label: Text('$m min'),
                      selected: _minutes == m,
                      onSelected: (_) => setState(() => _minutes = m),
                    ),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Styrke: ${_days >= 4 ? 2 : 1} per uke · Ute: ${_days >= 4 ? _days - 2 : 2} per uke. Langturen blir lengre enn vanlige økter.',
                  style: const TextStyle(color: muted, fontSize: 14),
                ),
              ]),
              const SizedBox(height: 12),
              _section('Aktiviteter du liker', [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (a, label) in [
                    (Activity.manualer, 'Manualer'),
                    (Activity.raskGange, 'Rask gange'),
                    (Activity.motbakker, 'Motbakker'),
                    (Activity.jogging, 'Jogging'),
                  ])
                    FilterChip(
                      label: Text(label),
                      selected: _activities.contains(a),
                      onSelected: (on) => setState(() => on ? _activities.add(a) : _activities.remove(a)),
                    ),
                ]),
              ]),
              const SizedBox(height: 12),
              _section('Helse', [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _health,
                  onChanged: (v) => setState(() => _health = v ?? false),
                  title: const Text('Jeg har hjerte- eller lungesykdom, eller får symptomer ved anstrengelse'),
                ),
              ]),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submit,
                child: Text(_adjust ? 'Lagre endringene' : 'Lag treningsplan'),
              ),
              if (_adjust) ...[
                const SizedBox(height: 8),
                Text(
                  from == 0
                      ? 'Planen har ikke startet ennå, så den lages på nytt.'
                      : 'Uke 1–$from beholdes som de er, med alt du har registrert. '
                          'Endringene gjelder fra uke ${from + 1}, og nivået fortsetter der du er nå.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
