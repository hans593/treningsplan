import 'package:flutter/material.dart';

import 'models.dart';

const muted = Color(0xFF55615A);
const warnBg = Color(0xFFFBEADF);
const warnFg = Color(0xFF8A3A10);

IconData iconFor(SessionType t) => switch (t) {
      SessionType.motbakke => Icons.terrain,
      SessionType.styrkeA || SessionType.styrkeB => Icons.fitness_center,
      SessionType.langtur => Icons.directions_walk,
      SessionType.kondisjon => Icons.directions_run,
      SessionType.restitusjon => Icons.self_improvement,
    };

String effortLabel(Effort e) => switch (e) {
      Effort.lett => 'rolig',
      Effort.moderat => 'middels',
      Effort.hard => 'hardt',
    };

String detailFor(Session s) => s.extra ? '${s.minutes} min · ${effortLabel(s.effort)}' : switch (s.type) {
      SessionType.motbakke => '${s.reps} × ${fmtSek(s.workSec)} · ${s.minutes} min',
      SessionType.styrkeA => '${s.rounds} runder · ${s.minutes} min',
      SessionType.styrkeB => '${s.workSec}/${s.restSec} sek · ${s.rounds} runder · ${s.minutes} min',
      _ => '${s.minutes} min',
    };

class SessionTile extends StatelessWidget {
  final Session session;
  final bool isToday;
  final VoidCallback onTap;
  const SessionTile({super.key, required this.session, required this.isToday, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final cs = Theme.of(context).colorScheme;
    final missed = s.status == SessionStatus.staattOver;
    final done = s.status == SessionStatus.fullfort;
    final fg = isToday ? Colors.white : const Color(0xFF17221C);
    final sub = isToday ? const Color(0xFFCFE3D7) : muted;

    Widget status;
    if (s.extra) {
      status = Text('+ Ekstra', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 13));
    } else if (done) {
      status = Text('✓ Fullført', style: TextStyle(color: isToday ? Colors.white : cs.primary, fontWeight: FontWeight.w600, fontSize: 13));
    } else if (missed) {
      final ok = s.resolution == Resolution.ekstraOkt;
      status = Text(s.resolved ? (s.note ?? 'Håndtert') : 'Stått over',
          style: TextStyle(
              color: ok ? cs.primary : (s.resolution == Resolution.forOppstart ? muted : const Color(0xFFB4501A)),
              fontWeight: FontWeight.w600,
              fontSize: 13));
    } else if (isToday) {
      status = const Text('I dag →', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13));
    } else {
      status = const SizedBox.shrink();
    }

    return Material(
      color: isToday ? cs.primary : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: isToday
                ? null
                : Border.all(
                    color: missed && !s.resolved ? const Color(0xFFC9824F) : const Color(0xFFDDE3DE),
                    width: missed && !s.resolved ? 1.5 : 1),
          ),
          child: Row(children: [
            SizedBox(
              width: 44,
              child: Column(children: [
                Text(ukedagerKort[s.date.weekday - 1], style: TextStyle(fontSize: 12, color: sub)),
                Text('${s.date.day}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: fg)),
              ]),
            ),
            const SizedBox(width: 10),
            Icon(iconFor(s.type), color: isToday ? Colors.white : cs.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg)),
                const SizedBox(height: 2),
                Text(s.note != null && !missed && s.note != 'Før oppstart' ? '${detailFor(s)} · ${s.note}' : detailFor(s),
                    style: TextStyle(fontSize: 13, color: sub)),
              ]),
            ),
            status,
          ]),
        ),
      ),
    );
  }
}

class StatBox extends StatelessWidget {
  final String label;
  final String value;
  const StatBox(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

/// Spør hvordan økta kjentes. Svaret justerer progresjonen.
Future<Feeling?> askFeeling(BuildContext context) => showModalBottomSheet<Feeling>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Hvordan kjentes økta?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Svaret brukes til å justere de neste øktene.', style: TextStyle(color: muted)),
            const SizedBox(height: 16),
            for (final (f, label) in [
              (Feeling.forLett, 'For lett'),
              (Feeling.passe, 'Passe'),
              (Feeling.forTungt, 'For tungt'),
            ]) ...[
              OutlinedButton(onPressed: () => Navigator.pop(ctx, f), child: Text(label)),
              const SizedBox(height: 8),
            ],
          ]),
        ),
      ),
    );
