import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models.dart';
import '../plan_generator.dart' show defaultDays;
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
  late int _minutes;
  late List<int> _trainingDays;
  late Set<Activity> _activities;
  late bool _health;
  late bool _hrUnreliable;
  late GoalType _goal;
  late final TextEditingController _maxHr;

  int get _days => _trainingDays.length;
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
    _trainingDays = [...(p?.trainingDays ?? defaultDays(p?.daysPerWeek ?? 4))]..sort();
    _hrUnreliable = p?.hrUnreliable ?? false;
    _goal = p?.goal ?? GoalType.vektned;
    _maxHr = TextEditingController(text: p?.maxHr?.toString() ?? '');
    _minutes = p?.minutesPerSession ?? 45;
    _activities = p?.activities.toSet() ?? {Activity.manualer, Activity.raskGange, Activity.motbakker, Activity.benk};
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
      // Planen kan vare i maks to år.
      lastDate: start ? DateTime(2035) : AppScope.of(context).latestEndDate(_start),
      locale: const Locale('nb'),
    );
    if (d == null) return;
    setState(() {
      if (start) {
        _start = d;
        if (!_end.isAfter(_start)) _end = _start.add(const Duration(days: 28));
        final latest = AppScope.of(context).latestEndDate(_start);
        if (_end.isAfter(latest)) _end = latest;
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
    if (_weeks > maxPlanWeeks) {
      _snack('Planen kan vare i maks $maxPlanWeeks uker (to år). Velg en tidligere måldato.');
      return;
    }
    if (_days < 3 || _days > 6) {
      _snack('Velg mellom 3 og 6 treningsdager.');
      return;
    }
    final weight = _num(_weight.text)!;
    final p = Profile(
      age: _num(_age.text)!.round(),
      heightCm: _num(_height.text)!.round(),
      weightKg: weight,
      targetKg: _goal == GoalType.holde ? weight : _num(_target.text)!,
      startDate: _start,
      endDate: _end,
      fitness: _fitness,
      intensity: _intensity,
      daysPerWeek: _days,
      minutesPerSession: _minutes,
      activities: _activities,
      healthWarning: _health,
      trainingDays: [..._trainingDays],
      maxHr: int.tryParse(_maxHr.text.trim()),
      hrUnreliable: _hrUnreliable,
      goal: _goal,
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
      final r = app.adjustPlan(p, currentWeightKg: changed ? p.weightKg : null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(from == 0
              ? 'Planen er laget på nytt'
              : r.ramped
                  ? 'Planen er justert fra uke ${from + 1}. Økningen trappes opp med maks 10 % per uke.'
                  : 'Planen er justert fra uke ${from + 1}')));
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

  Widget _dayChips() => Wrap(spacing: 6, runSpacing: 6, children: [
        for (var d = 0; d < 7; d++)
          FilterChip(
            label: Text(ukedagerKort[d].substring(0, 1) + ukedagerKort[d].substring(1).toLowerCase()),
            tooltip: ukedager[d],
            selected: _trainingDays.contains(d),
            onSelected: (on) => setState(() {
              if (on && _trainingDays.length < 6) _trainingDays.add(d);
              if (!on && _trainingDays.length > 3) _trainingDays.remove(d);
              _trainingDays.sort();
            }),
          ),
      ]);

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
                SegmentedButton<GoalType>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: GoalType.vektned, label: Text('Gå ned i vekt')),
                    ButtonSegment(value: GoalType.holde, label: Text('Holde vekten / bedre form')),
                  ],
                  selected: {_goal},
                  onSelectionChanged: (s) => setState(() => _goal = s.first),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _field(_adjust ? 'Vekt i dag' : 'Vekt nå', _weight, 35, 250, 'kg')),
                  if (_goal == GoalType.vektned) ...[
                    const SizedBox(width: 12),
                    Expanded(child: _field('Målvekt', _target, 35, 250, 'kg')),
                  ],
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
                    perWeek == null || _goal == GoalType.holde
                        ? '$_weeks uker${_adjust ? ' ($_weeksLeft igjen)' : ''}'
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
                Text('Treningsdager: $_days per uke', style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 4),
                const Text('Velg 3–6 dager. Appen legger intervallene der du har hviledag etter, og langturen i helga hvis mulig.',
                    style: TextStyle(color: muted, fontSize: 14)),
                const SizedBox(height: 8),
                _dayChips(),
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
              _section('Aktiviteter og utstyr', [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (a, label) in [
                    (Activity.motbakker, 'Motbakker'),
                    (Activity.jogging, 'Jogging'),
                    (Activity.raskGange, 'Rask gange'),
                    (Activity.manualer, 'Manualer'),
                    (Activity.benk, 'Stødig stol eller benk'),
                  ])
                    FilterChip(
                      label: Text(label),
                      selected: _activities.contains(a),
                      onSelected: (on) => setState(() => on ? _activities.add(a) : _activities.remove(a)),
                    ),
                ]),
                const SizedBox(height: 8),
                Text(
                  _activities.contains(Activity.manualer)
                      ? 'Styrkeøktene bruker manualene.'
                      : 'Uten manualer får du øvelser med egen kroppsvekt.',
                  style: const TextStyle(color: muted, fontSize: 14),
                ),
              ]),
              const SizedBox(height: 12),
              _section('Helse', [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _health,
                  onChanged: (v) => setState(() => _health = v ?? false),
                  title: const Text('Jeg har hjerte- eller lungesykdom, eller får symptomer ved anstrengelse'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _maxHr,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Egen makspuls (valgfritt)',
                    helperText: 'Tom = anslått ut fra alder (${_num(_age.text) == null ? 'ca. 208 − 0,7 × alder' : 'ca. ${(208 - 0.7 * _num(_age.text)!).round()}'})',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final n = int.tryParse(v);
                    return n == null || n < 100 || n > 220 ? 'Mellom 100 og 220' : null;
                  },
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _hrUnreliable,
                  onChanged: (v) => setState(() => _hrUnreliable = v ?? false),
                  title: const Text('Jeg bruker medisin som påvirker pulsen (f.eks. betablokker)'),
                  subtitle: const Text('Da brukes ikke pulsen fra klokka til å bedømme hvor hard økta var.'),
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
                          'Endringene gjelder fra uke ${from + 1}. Mer trening trappes opp med maks 10 % per uke.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
