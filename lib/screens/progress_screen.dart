import 'dart:math';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../state.dart';
import '../exercises.dart';
import '../widgets.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.profile!;
    final latest = app.measurements.where((m) => m.weightKg != null).lastOrNull;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            const Text('Fremgang', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: StatBox('Vekt nå', latest == null ? '–' : '${fmtKg(latest.weightKg!)} kg')),
              const SizedBox(width: 8),
              Expanded(
                  child: StatBox(p.holdsWeight ? 'Mål' : 'Plan i dag',
                      p.holdsWeight ? 'Holde ${fmtKg(p.weightKg)}' : '${fmtKg(app.plannedWeight(app.today))} kg')),
              const SizedBox(width: 8),
              Expanded(
                  child: StatBox('Økter', '${app.sessionsDone}/${app.sessionsSoFar}${app.extrasDone > 0 ? ' +${app.extrasDone}' : ''}')),
            ]),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                        child: Text(p.holdsWeight ? 'Vekt' : 'Vekt mot mål',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                    Text(p.holdsWeight ? 'Holde vekten' : '${fmtKg(p.weightKg)} → ${fmtKg(p.targetKg)} kg',
                        style: const TextStyle(color: muted, fontSize: 15)),
                  ]),
                  const SizedBox(height: 12),
                  Semantics(
                    label: 'Vektkurve: plan fra ${fmtKg(p.weightKg)} til ${fmtKg(p.targetKg)} kg, '
                        'og ${app.measurements.length} registreringer',
                    child: SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: CustomPaint(painter: _WeightChart(app)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    _legend(cs.primary, 'Plan', dashed: true),
                    const SizedBox(width: 16),
                    _legend(brandOrange, 'Dine målinger'),
                  ]),
                  const SizedBox(height: 8),
                  const Text('Vei deg 2–3 morgener i uken. Svingninger fra dag til dag er normalt.',
                      style: TextStyle(color: muted, fontSize: 14)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _editMeasurement(context, app, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Registrer vekt og midjemål'),
                  ),
                  if (app.measurements.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text('Alle målinger (${app.measurements.length})', style: const TextStyle(fontSize: 15)),
                      children: [
                        for (final m in app.measurements.reversed)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(fmtDatoLang(m.date)),
                            subtitle: Text([
                              if (m.weightKg != null) '${fmtKg(m.weightKg!)} kg',
                              if (m.waistCm != null) 'midje ${fmtKg(m.waistCm!)} cm',
                            ].join(' · ')),
                            trailing: const Icon(Icons.edit_outlined),
                            onTap: () => _editMeasurement(context, app, m),
                          ),
                      ],
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Tester', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('Ved start, midtveis og på måldatoen. Registrerer du samme dag igjen, erstattes testen.',
                      style: TextStyle(color: muted, fontSize: 14)),
                  const SizedBox(height: 8),
                  if (app.tests.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Ingen tester registrert ennå.'),
                    ),
                  for (final t in app.tests)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(fmtDatoLang(t.date), style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([
                        if (t.squats60s != null) 'Knebøy: ${t.squats60s}',
                        if (t.plankSec != null) 'Planke: ${t.plankSec} s',
                        if (t.walk3kmSec != null)
                          '3 km: ${t.walk3kmSec! ~/ 60}:${(t.walk3kmSec! % 60).toString().padLeft(2, '0')}',
                        if (t.hillBreath != null) 'Pust i bakke: ${t.hillBreath}/10',
                      ].join(' · '), style: const TextStyle(color: muted, fontSize: 15)),
                      trailing: IconButton(
                        tooltip: 'Slett test',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: Text('Slette testen fra ${fmtDato(t.date)}?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Avbryt')),
                                TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Slett')),
                              ],
                            ),
                          );
                          if (ok == true) app.deleteTest(t);
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _addTest(context, app),
                    icon: const Icon(Icons.add),
                    label: const Text('Registrer test'),
                  ),
                ]),
              ),
            ),
            if (app.loggedExercises.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Styrke', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const Text('Tyngste vekt du har registrert per øvelse.', style: TextStyle(color: muted, fontSize: 14)),
                    const SizedBox(height: 8),
                    for (final id in app.loggedExercises)
                      Builder(builder: (context) {
                        final h = app.strengthHistory(id);
                        if (h.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(children: [
                            ExerciseFigure(id, size: 40),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(exercises[id]?.name ?? id, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                Text(
                                  h.length == 1
                                      ? '${fmtKg(h.first.$2)} kg'
                                      : '${fmtKg(h.first.$2)} → ${fmtKg(h.last.$2)} kg (${h.length} økter)',
                                  style: const TextStyle(color: muted, fontSize: 14),
                                ),
                              ]),
                            ),
                            SizedBox(width: 80, height: 32, child: CustomPaint(painter: _Spark([for (final x in h) x.$2]))),
                          ]),
                        );
                      }),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Kosthold for målet', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  p.holdsWeight
                      ? 'Målet er å holde vekten og bli i bedre form. Spis variert, med protein til hvert måltid.'
                      : 'Ca. ${(p.dailyDeficitKcal / 50).round() * 50} kcal underskudd per dag gir rundt '
                          '${p.kgPerWeek.toStringAsFixed(2).replaceAll('.', ',')} kg ned per uke. '
                          'Protein til hvert måltid hjelper deg å beholde musklene.',
                  style: const TextStyle(fontSize: 15, height: 1.45),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color c, String label, {bool dashed = false}) => Row(children: [
        Container(width: 18, height: 3, color: dashed ? c.withValues(alpha: 0.6) : c),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 14, color: muted)),
      ]);

  /// Ny måling (m == null) eller rett/slett en eksisterende.
  Future<void> _editMeasurement(BuildContext context, AppState app, Measurement? m) async {
    final w = TextEditingController(text: m?.weightKg == null ? '' : fmtKg(m!.weightKg!));
    final waist = TextEditingController(text: m?.waistCm == null ? '' : fmtKg(m!.waistCm!));
    var date = m?.date ?? app.today;
    String? error;
    double? n(String s) => s.trim().isEmpty ? null : double.tryParse(s.replaceAll(',', '.').trim());
    final result = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(m == null ? 'Ny måling' : 'Endre måling'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(date == app.today ? 'I dag' : fmtDatoLang(date)),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () async {
                  final d = await showDatePicker(
                      context: c, initialDate: date, firstDate: DateTime(2020), lastDate: app.today);
                  if (d != null) set(() => date = d);
                },
              ),
              TextField(
                  controller: w,
                  autofocus: m == null,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Vekt (kg)')),
              const SizedBox(height: 12),
              TextField(
                  controller: waist,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Midjemål (cm, valgfritt)')),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 14)),
                ),
            ]),
          ),
          actions: [
            if (m != null) TextButton(onPressed: () => Navigator.pop(c, 'slett'), child: const Text('Slett')),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Avbryt')),
            TextButton(
              onPressed: () {
                final kg = n(w.text), cm = n(waist.text);
                final err = (w.text.trim().isNotEmpty && kg == null)
                    ? 'Skriv vekten som et tall, f.eks. 94,5'
                    : validateWeight(kg) ?? validateWaist(cm) ?? (kg == null && cm == null ? 'Fyll inn vekt eller midjemål' : null);
                if (err != null) {
                  set(() => error = err);
                  return;
                }
                Navigator.pop(c, 'lagre');
              },
              child: const Text('Lagre'),
            ),
          ],
        ),
      ),
    );
    if (result == 'slett' && m != null) {
      app.deleteMeasurement(m);
    } else if (result == 'lagre') {
      final nm = Measurement(date: date, weightKg: n(w.text), waistCm: n(waist.text));
      if (m == null) {
        app.addMeasurement(nm);
      } else {
        app.updateMeasurement(m, nm);
      }
    }
  }

  Future<void> _addTest(BuildContext context, AppState app) async {
    final squats = TextEditingController(), plank = TextEditingController();
    final walk = TextEditingController(), breath = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Test i dag'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: squats,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Knebøy til stol på 60 sek (antall)')),
            const SizedBox(height: 10),
            TextField(
                controller: plank,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Planke (sekunder, maks 60)')),
            const SizedBox(height: 10),
            TextField(
                controller: walk,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(labelText: 'Fast 3 km tur (mm:ss)')),
            const SizedBox(height: 10),
            TextField(
                controller: breath,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Pust i motbakke (1–10)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Avbryt')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Lagre')),
        ],
      ),
    );
    if (ok != true) return;
    int? walkSec;
    final parts = walk.text.split(RegExp(r'[:.,]'));
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]), s = int.tryParse(parts[1]);
      if (m != null && s != null) walkSec = m * 60 + s;
    } else if (int.tryParse(walk.text) != null) {
      walkSec = int.parse(walk.text) * 60;
    }
    app.addTest(TestResult(
      date: app.today,
      squats60s: int.tryParse(squats.text),
      plankSec: int.tryParse(plank.text)?.clamp(0, 60),
      walk3kmSec: walkSec,
      hillBreath: int.tryParse(breath.text)?.clamp(1, 10),
    ));
  }
}

/// Liten kurve for styrkeutvikling.
class _Spark extends CustomPainter {
  final List<double> v;
  _Spark(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    final lo = v.reduce(min), hi = v.reduce(max);
    final span = hi - lo == 0 ? 1 : hi - lo;
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = size.width * i / (v.length - 1);
      final y = size.height - 4 - (size.height - 8) * (v[i] - lo) / span;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = brandGreen
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _Spark old) => true;
}

class _WeightChart extends CustomPainter {
  final AppState app;
  _WeightChart(this.app);

  @override
  void paint(Canvas canvas, Size size) {
    final p = app.profile!;
    final weights = app.measurements.where((m) => m.weightKg != null).toList();
    final values = [p.weightKg, p.targetKg, ...weights.map((m) => m.weightKg!)];
    final hi = (values.reduce(max) + 1).ceilToDouble();
    final lo = (values.reduce(min) - 1).floorToDouble();
    const left = 34.0, bottom = 22.0;
    final w = size.width - left - 6, h = size.height - bottom - 6;
    final total = max(1, p.endDate.difference(p.startDate).inDays);

    double x(DateTime d) => left + w * (d.difference(p.startDate).inDays.clamp(0, total) / total);
    double y(double kg) => 6 + h * (hi - kg) / (hi - lo);

    final grid = Paint()..color = const Color(0xFFE5EAE6);
    final label = TextStyle(color: muted, fontSize: 11);
    for (final kg in [hi, (hi + lo) / 2, lo]) {
      canvas.drawLine(Offset(left, y(kg)), Offset(size.width, y(kg)), grid);
      _text(canvas, kg.toStringAsFixed(0), Offset(0, y(kg) - 7), label);
    }
    // Månedsetiketter
    var d = DateTime(p.startDate.year, p.startDate.month, 1);
    while (!d.isAfter(p.endDate)) {
      if (!d.isBefore(p.startDate)) {
        _text(canvas, maanederKort[d.month - 1], Offset(x(d) - 8, size.height - 16), label);
      }
      d = DateTime(d.year, d.month + 1, 1);
    }
    // Planlinje (stiplet)
    final plan = Paint()
      ..color = brandGreen
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final a = Offset(x(p.startDate), y(p.weightKg)), b = Offset(x(p.endDate), y(p.targetKg));
    final len = (b - a).distance;
    for (double t = 0; t < len; t += 11) {
      final s = a + (b - a) * (t / len), e = a + (b - a) * (min(t + 6, len) / len);
      canvas.drawLine(s, e, plan);
    }
    canvas.drawCircle(b, 4.5, Paint()..color = brandGreen);
    // Målinger
    final line = Paint()
      ..color = brandOrange
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var i = 0; i < weights.length; i++) {
      final pt = Offset(x(weights[i].date), y(weights[i].weightKg!));
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      canvas.drawCircle(pt, 3.5, Paint()..color = brandOrange);
    }
    canvas.drawPath(path, line);
  }

  void _text(Canvas c, String s, Offset o, TextStyle st) {
    final tp = TextPainter(text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, o);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
