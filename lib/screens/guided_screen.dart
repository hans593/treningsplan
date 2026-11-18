import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../exercises.dart';
import '../main.dart';
import '../models.dart';
import '../widgets.dart';
import '../workout_steps.dart';

class GuidedScreen extends StatefulWidget {
  final Session session;
  const GuidedScreen({super.key, required this.session});

  @override
  State<GuidedScreen> createState() => _GuidedScreenState();
}

class _GuidedScreenState extends State<GuidedScreen> {
  late List<WorkoutStep> _steps;
  int _i = 0;
  DateTime? _endsAt; // slutt for tidsstyrt steg
  Duration? _pausedLeft;
  Timer? _ticker;
  final _started = DateTime.now();
  bool _finished = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ticker == null) {
      _steps = stepsFor(widget.session, senior: AppScope.of(context).profile?.isSenior ?? false);
      _startStep();
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  WorkoutStep get _step => _steps[_i];

  void _startStep({Duration carry = Duration.zero}) {
    final sec = _step.seconds;
    _endsAt = sec == null ? null : DateTime.now().add(Duration(seconds: sec)).subtract(carry);
    _pausedLeft = null;
  }

  Duration get _left {
    if (_pausedLeft != null) return _pausedLeft!;
    if (_endsAt == null) return Duration.zero;
    return _endsAt!.difference(DateTime.now());
  }

  void _tick() {
    if (_finished || _pausedLeft != null || _endsAt == null) {
      setState(() {});
      return;
    }
    // Ta igjen steg som gikk ut mens skjermen var av.
    var left = _left;
    var advanced = false;
    while (left <= Duration.zero && _endsAt != null) {
      if (_i >= _steps.length - 1) {
        _finish();
        return;
      }
      _i++;
      advanced = true;
      _startStep(carry: -left);
      left = _left;
    }
    if (advanced) _signal();
    setState(() {});
  }

  void _signal() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
  }

  void _next() {
    if (_i >= _steps.length - 1) {
      _finish();
      return;
    }
    setState(() {
      _i++;
      _startStep();
    });
    _signal();
  }

  void _togglePause() {
    setState(() {
      if (_pausedLeft != null) {
        _endsAt = DateTime.now().add(_pausedLeft!);
        _pausedLeft = null;
      } else if (_endsAt != null) {
        _pausedLeft = _left;
      }
    });
  }

  Future<void> _finish() async {
    if (_finished) return;
    _finished = true;
    _ticker?.cancel();
    _signal();
    final app = AppScope.of(context);
    final f = await askFeeling(context);
    app.markDone(widget.session, feeling: f ?? Feeling.passe);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _quit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Avslutte økta?'),
        content: const Text('Du kan fullføre den senere, eller markere den som gjennomført.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Fortsett økta')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Avslutt')),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.pop(context);
  }

  String _fmt(Duration d) {
    final s = d.inMilliseconds <= 0 ? 0 : (d.inMilliseconds / 1000).ceil();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final step = _step;
    final cs = Theme.of(context).colorScheme;
    final timed = step.seconds != null;
    final bg = step.isRest ? const Color(0xFF2F6E55) : cs.primary;
    final elapsed = DateTime.now().difference(_started);
    final next = _i < _steps.length - 1 ? _steps[_i + 1] : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _quit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.session.title),
          leading: IconButton(tooltip: 'Avslutt', icon: const Icon(Icons.close), onPressed: _quit),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text('Steg ${_i + 1} av ${_steps.length}',
                          style: const TextStyle(color: Color(0xFFCFE3D7), fontWeight: FontWeight.w600)),
                    ),
                    if (step.isWork)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: brandOrange, borderRadius: BorderRadius.circular(99)),
                        child: const Text('JOBB', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                    if (step.isRest)
                      const Text('PAUSE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                  ]),
                  const SizedBox(height: 10),
                  Text(step.title,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (timed)
                    Text(_fmt(_left),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 84, fontWeight: FontWeight.w700, height: 1,
                            fontFeatures: [FontFeature.tabularFigures()]))
                  else
                    Text(step.subtitle,
                        style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w700)),
                  if (timed) ...[
                    const SizedBox(height: 8),
                    Text(step.subtitle, style: const TextStyle(color: Color(0xFFE6F0EA), fontSize: 15)),
                  ],
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (_i + 1) / _steps.length,
                      minHeight: 6,
                      color: Colors.white,
                      backgroundColor: const Color(0xFF3F7A60),
                    ),
                  ),
                ]),
              ),
              if (step.exerciseId != null) ...[
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: () => _showCue(step.exerciseId!),
                    child: ExerciseFigure(step.exerciseId!, size: 180),
                  ),
                ),
                const SizedBox(height: 8),
                Text(exercises[step.exerciseId!]!.cue,
                    textAlign: TextAlign.center, style: const TextStyle(color: muted, fontSize: 14)),
              ],
              const SizedBox(height: 16),
              if (next != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.arrow_forward),
                    title: Text('Neste: ${next.title}'),
                    subtitle: next.seconds != null ? Text(fmtSek(next.seconds!)) : Text(next.subtitle),
                  ),
                ),
              const SizedBox(height: 8),
              Text('Total tid: ${_fmt(elapsed)}', textAlign: TextAlign.center, style: const TextStyle(color: muted)),
              const SizedBox(height: 16),
              if (timed)
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _togglePause,
                      child: Text(_pausedLeft != null ? 'Fortsett' : 'Pause'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton(onPressed: _next, child: const Text('Hopp over'))),
                ])
              else
                FilledButton(onPressed: _next, child: const Text('Ferdig – neste')),
              const SizedBox(height: 10),
              TextButton(onPressed: _finish, child: const Text('Fullfør økta nå')),
              if (widget.session.type == SessionType.motbakke || widget.session.type == SessionType.kondisjon)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Stopp ved brystsmerter, svimmelhet eller uvanlig tung pust.',
                      textAlign: TextAlign.center, style: TextStyle(color: warnFg, fontSize: 13)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCue(String id) {
    final ex = exercises[id]!;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(ex.name),
        content: Text('${ex.cue}\n\nLettere: ${ex.easier}'),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }
}
