// Stemme, musikk og våken skjerm under guidet økt.
//
// * Stemmen bruker telefonens norske tale (nb-NO).
// * «Appens musikk» spiller to egne låter: en energisk under arbeid og en rolig i pauser.
//   Musikken dempes mens stemmen snakker.
// * «Egen musikk» lar Spotify, radio eller podkast spille videre; den dempes kort mens stemmen snakker.

import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'models.dart';

class Coach {
  Coach({required this.voice, required this.music, this.genre = MusicGenre.pop, this.keepScreenOn = true});

  /// Styrke: skjermen holdes på. Tur: skjermen kan slukkes, tjenesten holder klokka i gang.
  final bool keepScreenOn;

  bool voice;
  MusicMode music;
  MusicGenre genre;

  final _tts = FlutterTts();
  AudioPlayer? _work;
  AudioPlayer? _rest;
  bool _restPhase = true;
  bool _paused = false;
  double _musicVolume = 0.8;

  Future<void> start() async {
    if (keepScreenOn) {
      try {
        await WakelockPlus.enable();
      } catch (_) {}
    }
    await _initTts();
    if (music == MusicMode.appen) await _startMusic();
  }

  Future<void> _initTts() async {
    try {
      var lang = 'nb-NO';
      for (final l in ['nb-NO', 'no-NO', 'nn-NO']) {
        if (await _tts.isLanguageAvailable(l) == true) {
          lang = l;
          break;
        }
      }
      await _tts.setLanguage(lang);
      await _tts.setSpeechRate(Platform.isIOS ? 0.48 : 0.5);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
      if (Platform.isAndroid) {
        // Talen spilles som «veiledning», over musikk fra andre apper.
        await _tts.setAudioAttributesForNavigation();
      } else if (Platform.isIOS) {
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ]);
      }
    } catch (e) {
      debugPrint('Tale ikke tilgjengelig: $e');
    }
  }

  Future<void> _startMusic() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _work = AudioPlayer(handleInterruptions: false);
      _rest = AudioPlayer(handleInterruptions: false);
      await _work!.setAsset(genre.workAsset);
      await _rest!.setAsset(genre.restAsset);
      for (final p in [_work!, _rest!]) {
        await p.setLoopMode(LoopMode.one);
      }
      await _work!.setVolume(0);
      await _rest!.setVolume(_musicVolume);
      _work!.play();
      _rest!.play();
    } catch (e) {
      debugPrint('Musikk feilet: $e');
      await _stopMusic();
    }
  }

  Future<void> _stopMusic() async {
    for (final p in [_work, _rest]) {
      try {
        await p?.stop();
        await p?.dispose();
      } catch (_) {}
    }
    _work = null;
    _rest = null;
  }

  /// Bytt mellom arbeids- og pausemusikk.
  Future<void> phase({required bool rest}) async {
    _restPhase = rest;
    await _applyVolumes();
  }

  Future<void> _applyVolumes({double duck = 1.0}) async {
    if (_work == null || _rest == null) return;
    final v = _musicVolume * duck;
    await _work!.setVolume(_restPhase ? 0 : v);
    await _rest!.setVolume(_restPhase ? v : 0);
  }

  Future<void> say(String text) async {
    if (!voice || text.isEmpty) return;
    try {
      await _tts.stop();
      await _applyVolumes(duck: 0.3);
      if (Platform.isAndroid) {
        // Uten appens musikk ber vi om kort lydfokus, så radio, podkast eller Spotify dempes
        // mens stemmen snakker og fortsetter etterpå.
        await _tts.speak(text, focus: music != MusicMode.appen);
      } else {
        await _tts.speak(text);
      }
    } catch (_) {
    } finally {
      await _applyVolumes();
    }
  }

  Future<void> setVoice(bool on) async {
    voice = on;
    if (!on) await _tts.stop();
  }

  Future<void> setMusic(MusicMode m) async {
    if (m == music) return;
    music = m;
    if (m == MusicMode.appen) {
      await _startMusic();
      if (_paused) await pause();
    } else {
      await _stopMusic();
    }
  }

  /// Bytt musikktype mens økta pågår.
  Future<void> setGenre(MusicGenre g) async {
    if (g == genre) return;
    genre = g;
    if (music != MusicMode.appen || _work == null) return;
    try {
      await _work!.setAsset(genre.workAsset);
      await _rest!.setAsset(genre.restAsset);
      await _applyVolumes();
      if (!_paused) {
        _work!.play();
        _rest!.play();
      }
    } catch (e) {
      debugPrint('Kunne ikke bytte musikk: $e');
    }
  }

  Future<void> pause() async {
    _paused = true;
    await _work?.pause();
    await _rest?.pause();
  }

  Future<void> resume() async {
    _paused = false;
    _work?.play();
    _rest?.play();
  }

  Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {}
    await _stopMusic();
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }
}
