import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treningsplan/state.dart';
import 'package:treningsplan/models.dart';
import 'package:treningsplan/plan_generator.dart';
import 'package:treningsplan/workout_steps.dart';

import 'plan_test.dart' show hansProfil;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final weeks = generatePlan(hansProfil());
  Session first(SessionType t, {int week = 0}) =>
      weeks.skip(week).expand((w) => w.sessions).firstWhere((s) => s.type == t);

  test('styrkeøkter er helt tidsstyrt, med klargjøring, oppvarming og nedtelling', () {
    for (final t in [SessionType.styrkeA, SessionType.styrkeB]) {
      final s = first(t, week: 6);
      final steps = stepsFor(s, senior: true);
      expect(steps.every((x) => x.seconds != null), isTrue, reason: '$t: alle steg skal ha tid');
      expect(steps.first.isPrepare, isTrue);
      expect(steps.first.speech, contains(t == SessionType.styrkeA ? 'Styrke A' : 'Styrke B'));
      expect(steps.first.speech, contains('Gjør deg klar'));
      expect(steps[1].speech, startsWith('Start økt'));
      final work = steps.where((x) => x.isWork).toList();
      expect(work.length, s.rounds * 5 + (t == SessionType.styrkeA ? s.rounds : 0));
      expect(work.every((x) => x.speech.contains('Start.') && x.countdown), isTrue);
      final rests = steps.where((x) => x.isRest).toList();
      expect(rests.every((x) => x.speech.startsWith('Pause. Hvil i') && x.speech.contains('Neste:')), isTrue);
      expect(steps.last.exerciseId, 'balanse');
    }
  });

  test('pausene følger planen (Styrke B 40/20, ny runde med lengre pause)', () {
    final s = first(SessionType.styrkeB, week: 6);
    expect(s.workSec, 40);
    final steps = stepsFor(s);
    expect(steps.where((x) => x.isWork).every((x) => x.seconds == 40), isTrue);
    final shortRests = steps.where((x) => x.isRest && x.title == 'Pause');
    expect(shortRests.every((x) => x.seconds == 20), isTrue);
    expect(steps.where((x) => x.title == 'Pause mellom runder').every((x) => x.seconds == 90), isTrue);
    // Første pause sier hvilken øvelse som kommer
    expect(shortRests.first.speech, contains('Neste: Armheving'));
  });

  test('opplest tekst er lett å si', () {
    expect(spoken('10–12 repetisjoner'), '10 til 12 repetisjoner');
    final s = first(SessionType.styrkeA);
    final speech = stepsFor(s).map((x) => x.speech).join(' ');
    expect(speech, isNot(contains('–')));
    expect(speech, contains('10 til 12 repetisjoner'));
    expect(speech, contains('Hvil i ett minutt'));
  });

  test('intervaller får opplesning per drag', () {
    final s = first(SessionType.motbakke, week: 8);
    final drag = stepsFor(s).where((x) => x.isWork).toList();
    expect(drag.length, s.reps);
    expect(drag.first.speech, contains('Drag 1 av ${s.reps}'));
  });

  test('alle musikktyper har lydfiler for arbeid og pause', () {
    for (final g in MusicGenre.values) {
      expect(File(g.workAsset).existsSync(), isTrue, reason: g.workAsset);
      expect(File(g.restAsset).existsSync(), isTrue, reason: g.restAsset);
    }
  });

  test('musikkvalg lagres og leses', () {
    final app = AppState(clock: () => DateTime(2026, 12, 1))..createPlan(hansProfil());
    app.setCoachSettings(genre: MusicGenre.klassisk, music: MusicMode.appen, voice: false);
    final copy = AppState()..fromJson(app.toJson());
    expect(copy.musicGenre, MusicGenre.klassisk);
    expect(copy.voiceOn, isFalse);
    expect((AppState()..fromJson({})).musicGenre, MusicGenre.pop);
  });

  test('ingen steg mangler opplesning', () {
    for (final w in weeks.take(8)) {
      for (final s in w.sessions) {
        expect(stepsFor(s, senior: true).every((x) => x.speech.trim().isNotEmpty), isTrue, reason: s.title);
      }
    }
  });
}
