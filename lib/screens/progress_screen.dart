import 'dart:math';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../state.dart';
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
              Expanded(child: StatBox('Plan i dag', '${fmtKg(app.plannedWeight(app.today))} kg')),
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
                    const Expanded(
                        child: Text('Vekt mot mål', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                    Text('${fmtKg(p.weightKg)} → ${fmtKg(p.targetKg)} kg', style: const TextStyle(color: muted)),
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
                      style: TextStyle(color: muted, fontSize: 13)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _addMeasurement(context, app),
                    icon: const Icon(Icons.add),
                    label: const Text('Registrer vekt og midjemål'),
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
                  const Text('Ved start, midtveis og på måldatoen.', style: TextStyle(color: muted, fontSize: 13)),
                  const SizedBox(height: 8),
                  if (app.tests.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Ingen tester registrert ennå.'),
                    ),
                  for (final t in app.tests)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(fmtDatoLang(t.date), style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text([
                          if (t.squats60s != null) 'Knebøy: ${t.squats60s}',
                          if (t.plankSec != null) 'Planke: ${t.plankSec} s',
                          if (t.walk3kmSec != null)
                            '3 km: ${t.walk3kmSec! ~/ 60}:${(t.walk3kmSec! % 60).toString().padLeft(2, '0')}',
                          if (t.hillBreath != null) 'Pust i bakke: ${t.hillBreath}/10',
                        ].join(' · '), style: const TextStyle(color: muted)),
                      ]),
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
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Kosthold for målet', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  p.kgPerWeek <= 0
                      ? 'Målet er å holde vekten. Spis variert med protein til hvert måltid.'
                      : 'Ca. ${(p.dailyDeficitKcal / 50).round() * 50} kcal underskudd per dag gir rundt '
                          '${p.kgPerWeek.toStringAsFixed(2).replaceAll('.', ',')} kg ned per uke. '
                          'Protein til hvert måltid hjelper deg å beholde musklene.',
                  style: const TextStyle(fontSize: 14, height: 1.45),
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
        Text(label, style: const TextStyle(fontSize: 13, color: muted)),
      ]);

  Future<void> _addMeasurement(BuildContext context, AppState app) async {
    final w = TextEditingController(), waist = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ny måling i dag'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: w,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Vekt (kg)')),
          const SizedBox(height: 12),
          TextField(
              controller: waist,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Midjemål (cm, valgfritt)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Avbryt')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Lagre')),
        ],
      ),
    );
    if (ok != true) return;
    double? n(String s) => double.tryParse(s.replaceAll(',', '.'));
    final kg = n(w.text), cm = n(waist.text);
    if (kg == null && cm == null) return;
    app.addMeasurement(Measurement(date: app.today, weightKg: kg, waistCm: cm));
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
