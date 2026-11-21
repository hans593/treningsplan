// Viser det klokka faktisk registrerte: tid, varighet, distanse, puls, pulssoner og pulskurve.

import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';
import '../widgets.dart';

const zoneColors = [
  Color(0xFF9DB8A8),
  Color(0xFF4F9A76),
  Color(0xFFE0A93B),
  Color(0xFFE07B39),
  Color(0xFFC2452D),
];

const zoneNames = ['Rolig', 'Lett', 'Middels', 'Hard', 'Maks'];
const zoneRanges = [(0.0, 0.6), (0.6, 0.7), (0.7, 0.8), (0.8, 0.9), (0.9, 1.2)];

String fmtVarighet(int sec) {
  final m = sec ~/ 60;
  if (m >= 60) return '${m ~/ 60} t ${m % 60} min';
  if (sec == 0) return '0 min';
  if (m == 0) return '<1 min';
  return '$m min';
}

String _kgKm(int m) => '${(m / 1000).toStringAsFixed(2).replaceAll('.', ',')} km';

String _pace(int secPerKm) => '${secPerKm ~/ 60}:${(secPerKm % 60).toString().padLeft(2, '0')} min/km';

/// Anstrengelse ut fra snittpuls (samme grenser som når klokkeøkter krysser av planen).
Effort effortFromAvg(int avg, int hrMax) {
  final pct = avg / hrMax;
  return pct < 0.64 ? Effort.lett : pct < 0.77 ? Effort.moderat : Effort.hard;
}

/// Pulsmål i prosent av makspuls for turøktene (styrke har ikke pulsmål).
(int, int)? pulseTarget(SessionType t) => switch (t) {
      SessionType.restitusjon => (50, 65),
      SessionType.langtur => (60, 75),
      SessionType.kondisjon => (65, 80),
      SessionType.motbakke => (70, 90),
      _ => null,
    };

/// Kort til økt-skjermen og klokkeloggen.
class WatchDetailsCard extends StatelessWidget {
  final WatchData data;
  final Session? planned;
  final bool hrUnreliable;
  const WatchDetailsCard(this.data, {super.key, this.planned, this.hrUnreliable = false});

  @override
  Widget build(BuildContext context) {
    final d = data;
    final cs = Theme.of(context).colorScheme;
    final durSec = d.end.difference(d.start).inSeconds;
    final tiles = <(String, String)>[
      ('Varighet', fmtVarighet(durSec)),
      if (d.distanceM != null && d.distanceM! > 0) ('Distanse', _kgKm(d.distanceM!)),
      if (d.paceSecPerKm != null) ('Tempo', _pace(d.paceSecPerKm!)),
      if (d.steps != null && d.steps! > 0) ('Skritt', '${d.steps}'),
      if (d.avgHr != null) ('Snittpuls', '${d.avgHr} slag/min'),
      if (d.maxHr != null) ('Høyeste puls', '${d.maxHr} slag/min'),
      if (d.minHr != null) ('Laveste puls', '${d.minHr} slag/min'),
      if (d.kcal != null && d.kcal! > 0) ('Kalorier', '${d.kcal} kcal'),
    ];
    final p = planned;
    final hrEffort = d.avgHr == null ? null : effortFromAvg(d.avgHr!, d.hrMaxUsed);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.watch, color: cs.primary),
            const SizedBox(width: 8),
            const Expanded(
                child: Text('Registrert av klokka', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 4),
          Text(
            '${d.activity} · ${fmtUkedag(d.start)} kl. ${fmtKl(d.start)}–${fmtKl(d.end)}'
            '${d.source.isNotEmpty ? '\nKilde: ${_sourceName(d.source)}' : ''}',
            style: const TextStyle(color: muted, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            final w = (c.maxWidth - 8) / 2;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (label, value) in tiles)
                Container(
                  width: w,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: const Color(0xFFEEF2EF), borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: const TextStyle(fontSize: 13, color: muted)),
                    const SizedBox(height: 2),
                    Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ]),
                ),
            ]);
          }),
          if (p != null) ...[
            const SizedBox(height: 12),
            _Compare(planned: p, data: d, hrEffort: hrUnreliable ? null : hrEffort),
          ],
          if (d.hasHr && !hrUnreliable) ...[
            const SizedBox(height: 16),
            Text('Tid i pulssoner (makspuls ${d.hrMaxUsed})',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _Zones(d),
          ],
          if (d.hrCurve.where((x) => x > 0).length >= 3) ...[
            const SizedBox(height: 16),
            const Text('Puls gjennom økta', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SizedBox(
              height: 130,
              width: double.infinity,
              child: Semantics(
                label: 'Pulskurve fra ${d.minHr} til ${d.maxHr} slag i minuttet',
                child: CustomPaint(painter: HrCurvePainter(d.hrCurve, d.hrMaxUsed)),
              ),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Text(fmtKl(d.start), style: const TextStyle(color: muted, fontSize: 13)),
              const Spacer(),
              Text(fmtKl(d.end), style: const TextStyle(color: muted, fontSize: 13)),
            ]),
          ],
          if (!d.hasHr) ...[
            const SizedBox(height: 12),
            const Text(
              'Klokka sendte ikke puls for denne økta. Sjekk at Samsung Health deler «Puls» med Health Connect.',
              style: TextStyle(color: muted, fontSize: 14),
            ),
          ],
          if (hrUnreliable && d.hasHr) ...[
            const SizedBox(height: 12),
            const Text('Du har oppgitt at medisin påvirker pulsen, så pulssonene vises ikke.',
                style: TextStyle(color: muted, fontSize: 14)),
          ],
          if (d.outcome.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(d.outcome, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
    );
  }

  static String _sourceName(String s) {
    if (s.contains('samsung') || s.contains('shealth') || s.startsWith('com.sec.')) return 'Samsung Health';
    if (s.contains('google') || s.contains('fit')) return 'Google Fit';
    return s;
  }
}

/// Plan mot det klokka målte.
class _Compare extends StatelessWidget {
  final Session planned;
  final WatchData data;
  final Effort? hrEffort;
  const _Compare({required this.planned, required this.data, this.hrEffort});

  @override
  Widget build(BuildContext context) {
    final diff = data.minutes - planned.minutes;
    final timeTxt = diff.abs() <= 2
        ? 'Tiden stemmer med planen (${planned.minutes} min).'
        : diff > 0
            ? '$diff min lenger enn planlagt (${planned.minutes} min).'
            : '${-diff} min kortere enn planlagt (${planned.minutes} min).';
    String? effTxt;
    if (hrEffort != null) {
      final pct = (data.avgHr! / data.hrMaxUsed * 100).round();
      final target = pulseTarget(planned.type);
      if (planned.type == SessionType.motbakke) {
        final top = data.maxHr == null ? 0 : (data.maxHr! / data.hrMaxUsed * 100).round();
        effTxt = 'Snittpuls $pct % av makspuls. Høyeste puls $top %'
            '${top >= 85 ? ' – dragene var harde nok (mål: over 85 %).' : ' – dragene kan tas litt hardere (mål: over 85 %).'}';
      } else if (target != null) {
        final (lo, hi) = target;
        final where = pct < lo
            ? 'litt roligere enn målet'
            : pct > hi
                ? 'litt hardere enn målet'
                : 'innenfor målet';
        effTxt = 'Snittpulsen var $pct % av makspuls – $where ($lo–$hi % for denne økta).';
      }
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD5DED8)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Mot planen', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(timeTxt, style: const TextStyle(fontSize: 14, height: 1.4)),
        if (effTxt != null) Text(effTxt, style: const TextStyle(fontSize: 14, height: 1.4)),
      ]),
    );
  }
}

class _Zones extends StatelessWidget {
  final WatchData d;
  const _Zones(this.d);

  @override
  Widget build(BuildContext context) {
    final total = max(1, d.zoneSec.fold<int>(0, (a, b) => a + b));
    return Column(children: [
      for (var z = 4; z >= 0; z--)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(
              width: 118,
              child: Text(
                '${zoneNames[z]} ${_range(z)}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: d.zoneSec[z] / total,
                  minHeight: 14,
                  color: zoneColors[z],
                  backgroundColor: const Color(0xFFEEF2EF),
                ),
              ),
            ),
            SizedBox(
              width: 58,
              child: Text(fmtVarighet(d.zoneSec[z]),
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
    ]);
  }

  String _range(int z) {
    final (a, b) = zoneRanges[z];
    final lo = (a * d.hrMaxUsed).round();
    final hi = (b * d.hrMaxUsed).round();
    if (z == 0) return '<$hi';
    if (z == 4) return '>$lo';
    return '$lo–$hi';
  }
}

/// Pulskurve per minutt med fargede sonebånd bak.
class HrCurvePainter extends CustomPainter {
  final List<int> curve;
  final int hrMax;
  HrCurvePainter(this.curve, this.hrMax);

  @override
  void paint(Canvas canvas, Size size) {
    final vals = curve.where((x) => x > 0).toList();
    if (vals.length < 2) return;
    final lo = (vals.reduce(min) - 8).toDouble();
    final hi = (vals.reduce(max) + 8).toDouble();
    double y(double bpm) => size.height - (bpm - lo) / (hi - lo) * size.height;

    // Sonebånd
    for (var z = 0; z < 5; z++) {
      final a = max(lo, zoneRanges[z].$1 * hrMax);
      final b = min(hi, zoneRanges[z].$2 * hrMax);
      if (b <= a) continue;
      canvas.drawRect(Rect.fromLTRB(0, y(b), size.width, y(a)),
          Paint()..color = zoneColors[z].withValues(alpha: 0.14));
    }
    final path = Path();
    var started = false;
    final n = curve.length;
    for (var i = 0; i < n; i++) {
      if (curve[i] <= 0) continue;
      final x = n == 1 ? 0.0 : i / (n - 1) * size.width;
      final py = y(curve[i].toDouble());
      if (!started) {
        path.moveTo(x, py);
        started = true;
      } else {
        path.lineTo(x, py);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFC2452D)
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final v in [hi - 8, lo + 8]) {
      tp.text = TextSpan(text: '${v.round()}', style: const TextStyle(color: muted, fontSize: 11));
      tp.layout();
      tp.paint(canvas, Offset(2, y(v) - tp.height - 1));
    }
  }

  @override
  bool shouldRepaint(covariant HrCurvePainter old) => old.curve != curve;
}

/// Liste over økter fra klokka.
class WatchLogTile extends StatelessWidget {
  final WatchData d;
  final VoidCallback onTap;
  const WatchLogTile(this.d, {super.key, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          onTap: onTap,
          leading: const Icon(Icons.watch),
          title: Text('${d.activity} · ${fmtVarighet(d.end.difference(d.start).inSeconds)}'),
          subtitle: Text([
            '${fmtUkedag(d.start)} kl. ${fmtKl(d.start)}',
            if (d.distanceM != null && d.distanceM! > 0) _kgKm(d.distanceM!),
            if (d.avgHr != null) 'snittpuls ${d.avgHr}',
          ].join(' · ')),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
}
