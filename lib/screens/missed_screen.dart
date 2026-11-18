import 'package:flutter/material.dart';

import '../compensation.dart';
import '../main.dart';
import '../models.dart';
import '../widgets.dart';
import 'extra_session_screen.dart';

class MissedScreen extends StatefulWidget {
  final Session missed;
  const MissedScreen({super.key, required this.missed});

  @override
  State<MissedScreen> createState() => _MissedScreenState();
}

class _MissedScreenState extends State<MissedScreen> {
  List<CompensationOption>? _options;
  int _picked = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_options == null) {
      _options = AppScope.of(context).optionsFor(widget.missed);
      final rec = _options!.indexWhere((o) => o.recommended);
      _picked = rec < 0 ? 0 : rec;
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.missed;
    final options = _options!;
    final o = options[_picked];
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          const Text('TAPT ØKT',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFB4501A), letterSpacing: 0.5)),
          Text('${m.title}, ${m.minutes} min', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          Text(fmtUkedag(m.date), style: const TextStyle(color: muted, fontSize: 15)),
          const SizedBox(height: 12),
          Material(
            color: const Color(0xFFEEF2EF),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pushReplacement(
                  context, MaterialPageRoute(builder: (_) => ExtraSessionScreen(initialDate: m.date.add(const Duration(days: 1))))),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(children: [
                  Icon(Icons.add_task),
                  SizedBox(width: 10),
                  Expanded(
                      child: Text('Har du allerede trent en annen dag? Registrer den som ekstra økt, så regnes den med.',
                          style: TextStyle(fontSize: 14))),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text('Hvordan vil du ta den igjen?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          RadioGroup<int>(
            groupValue: _picked,
            onChanged: (v) => setState(() => _picked = v!),
            child: Column(children: [
              for (var i = 0; i < options.length; i++) ...[
                Material(
                  color: i == _picked ? cs.primaryContainer : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: i == _picked ? cs.primary : const Color(0xFFDDE3DE), width: i == _picked ? 2 : 1),
                  ),
                  child: RadioListTile<int>(
                    value: i,
                    title: Text.rich(TextSpan(children: [
                      TextSpan(text: options[i].title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (options[i].recommended)
                        TextSpan(
                            text: '  Anbefalt',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
                    ])),
                    subtitle: Text(options[i].description),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ]),
          ),
          const SizedBox(height: 6),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Slik endres planen', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final c in o.changes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.dag, style: const TextStyle(fontSize: 13, color: muted, fontWeight: FontWeight.w600)),
                      Text.rich(TextSpan(children: [
                        TextSpan(
                            text: c.fra,
                            style: const TextStyle(color: muted, decoration: TextDecoration.lineThrough)),
                        const TextSpan(text: '  →  '),
                        TextSpan(text: c.til, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ])),
                    ]),
                  ),
                Text(o.summary, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFEEF2EF), borderRadius: BorderRadius.circular(14)),
            child: const Text(
              'Regler appen følger:\n'
              '• Maks 10 % økning i ukentlig treningsmengde\n'
              '• Aldri to harde økter to dager på rad\n'
              '• Tapte intervaller dobles aldri opp\n'
              '• Står du over 3 økter på 2 uker, går progresjonen én uke tilbake',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              AppScope.of(context).applyCompensation(o, m);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Planen er oppdatert')));
            },
            child: const Text('Bruk dette forslaget'),
          ),
        ],
      ),
    );
  }
}
