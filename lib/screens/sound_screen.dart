import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import '../main.dart';
import '../models.dart';
import '../widgets.dart';

/// Valg av stemme og musikk under økta, med mulighet for å prøvelytte.
class SoundScreen extends StatefulWidget {
  const SoundScreen({super.key});

  @override
  State<SoundScreen> createState() => _SoundScreenState();
}

class _SoundScreenState extends State<SoundScreen> {
  final _player = AudioPlayer();
  final _tts = FlutterTts();
  String? _playing; // asset som spilles nå

  static const _desc = {
    MusicGenre.rolig: 'Myk akustisk gitar og piano. Rolig tempo.',
    MusicGenre.piano: 'Piano med lett beat i arbeid, rolig piano i pausene.',
    MusicGenre.rock: 'Elgitar og trommer i høyt tempo.',
    MusicGenre.pop: 'Elektronisk pop med tydelig takt.',
    MusicGenre.klassisk: 'Strykere i barokkstil i arbeid, rolig adagio i pausene.',
  };

  @override
  void dispose() {
    _player.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _preview(String asset) async {
    if (_playing == asset) {
      await _player.stop();
      setState(() => _playing = null);
      return;
    }
    setState(() => _playing = asset);
    try {
      await _player.setAsset(asset);
      await _player.seek(const Duration(seconds: 20));
      await _player.setVolume(0.8);
      await _player.play();
    } catch (_) {
      if (mounted) setState(() => _playing = null);
    }
  }

  Future<void> _testVoice() async {
    try {
      await _tts.setLanguage('nb-NO');
      await _tts.setSpeechRate(0.5);
      await _tts.speak('Start. Knebøy med manual. 12 til 15 repetisjoner.');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Lyd, musikk og pauser')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Card(
            child: SwitchListTile(
              title: const Text('Stemmesignal'),
              subtitle: const Text('Sier øvelse, start, pause og teller ned'),
              value: app.voiceOn,
              onChanged: (v) => app.setCoachSettings(voice: v),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _testVoice,
              icon: const Icon(Icons.record_voice_over),
              label: const Text('Prøv stemmen'),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Pauser', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Lengre pauser mellom sett og intervaller. Det er alltid trygt å hvile mer.',
              style: TextStyle(color: muted, fontSize: 14)),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Normale')),
              ButtonSegment(value: 15, label: Text('+15 s')),
              ButtonSegment(value: 30, label: Text('+30 s')),
              ButtonSegment(value: 60, label: Text('+60 s')),
            ],
            selected: {app.extraRestSec},
            onSelectionChanged: (s) => app.setCoachSettings(extraRest: s.first),
          ),
          const SizedBox(height: 20),
          const Text('Musikk under økta', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SegmentedButton<MusicMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: MusicMode.appen, label: Text('Appens')),
              ButtonSegment(value: MusicMode.egen, label: Text('Egen')),
              ButtonSegment(value: MusicMode.av, label: Text('Ingen')),
            ],
            selected: {app.musicMode},
            onSelectionChanged: (s) => app.setCoachSettings(music: s.first),
          ),
          const SizedBox(height: 6),
          Text(
            switch (app.musicMode) {
              MusicMode.appen => 'Egne låter: en energisk under arbeid og en rolig i pausene.',
              MusicMode.egen => 'Start Spotify eller annen musikk før økta. Den dempes kort når stemmen snakker.',
              MusicMode.av => 'Bare stemme og klokke.',
            },
            style: const TextStyle(color: muted, fontSize: 14),
          ),
          if (app.musicMode == MusicMode.appen) ...[
            const SizedBox(height: 16),
            const Text('Musikktype', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            RadioGroup<MusicGenre>(
              groupValue: app.musicGenre,
              onChanged: (g) => app.setCoachSettings(genre: g),
              child: Column(children: [
                for (final g in MusicGenre.values) ...[
                  Material(
                    color: g == app.musicGenre ? cs.primaryContainer : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: g == app.musicGenre ? cs.primary : const Color(0xFFDDE3DE)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Row(children: [
                        Expanded(
                          child: RadioListTile<MusicGenre>(
                            value: g,
                            title: Text(g.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(_desc[g]!),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Prøvelytt ${g.label.toLowerCase()} – arbeid',
                          icon: Icon(_playing == g.workAsset ? Icons.stop_circle : Icons.play_circle),
                          onPressed: () => _preview(g.workAsset),
                        ),
                        IconButton(
                          tooltip: 'Prøvelytt ${g.label.toLowerCase()} – pause',
                          icon: Icon(_playing == g.restAsset ? Icons.stop_circle : Icons.self_improvement),
                          onPressed: () => _preview(g.restAsset),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ]),
            ),
            const Text('Den første knappen spiller arbeidsmusikken, den andre pausemusikken. Du kan også bytte type underveis i økta (notetegnet øverst).',
                style: TextStyle(color: muted, fontSize: 14)),
          ],
        ],
      ),
    );
  }
}
