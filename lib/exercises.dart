// Øvelsesbibliotek med tegnede figurer (strektegninger i et 72 × 72-rutenett).

import 'package:flutter/material.dart';

import 'models.dart';

sealed class Prim {
  const Prim();
}

/// Kroppslinje.
class Line extends Prim {
  final List<Offset> pts;
  const Line(this.pts);
}

/// Hode.
class Head extends Prim {
  final Offset c;
  const Head(this.c);
}

/// Manual (fylt rektangel).
class Db extends Prim {
  final Rect r;
  const Db(this.r);
}

/// Gulv, matte, benk (grå).
class Prop extends Prim {
  final List<Offset> pts;
  final double width;
  const Prop(this.pts, {this.width = 2});
}

class Exercise {
  final String id;
  final String name;
  final String muscles;
  final String cue;
  final String easier;
  final List<Prim> figure;
  const Exercise(this.id, this.name, this.muscles, this.cue, this.easier, this.figure);
}

const _floor = Prop([Offset(8, 61), Offset(64, 61)]);
const _mat = Prop([Offset(4, 56), Offset(68, 56)], width: 4);

const exercises = <String, Exercise>{
  'knebøy': Exercise('knebøy', 'Knebøy', 'Lår, sete og kjerne',
      'Hold en manual (eller hendene) foran brystet. Sett deg bakover som mot en stol, knærne følger tærne. Rett rygg.',
      'Knebøy ned til en stol', [
    _floor, Head(Offset(38, 13)), Line([Offset(37, 19), Offset(31, 38)]),
    Line([Offset(31, 38), Offset(46, 40), Offset(44, 60)]), Line([Offset(35, 25), Offset(42, 29)]),
    Db(Rect.fromLTWH(40, 25, 8, 8)),
  ]),
  'roing': Exercise('roing', 'Foroverbøyd roing', 'Rygg og armer',
      'Bøy i hoften med rett rygg og myke knær. Trekk manualene opp mot hoftene, senk rolig.',
      'Stå mer oppreist, lettere vekt', [
    _floor, Head(Offset(18, 22)), Line([Offset(23, 25), Offset(44, 32)]),
    Line([Offset(44, 32), Offset(40, 46), Offset(42, 60)]), Line([Offset(30, 28), Offset(33, 42)]),
    Db(Rect.fromLTWH(28, 42, 11, 6)),
  ]),
  'enarmsroing': Exercise('enarmsroing', 'Enarms roing med støtte', 'Rygg og armer',
      'Støtt en hånd på stol eller benk. Trekk manualen opp langs siden, albuen nær kroppen.',
      'Lettere vekt, færre repetisjoner', [
    _floor, Prop([Offset(10, 40), Offset(26, 40)], width: 3), Prop([Offset(12, 40), Offset(12, 61)], width: 3),
    Head(Offset(18, 22)), Line([Offset(23, 25), Offset(44, 32)]), Line([Offset(25, 26), Offset(20, 40)]),
    Line([Offset(44, 32), Offset(40, 46), Offset(42, 60)]), Line([Offset(32, 29), Offset(34, 40)]),
    Db(Rect.fromLTWH(29, 40, 11, 6)),
  ]),
  'brystpress': Exercise('brystpress', 'Brystpress på matte', 'Bryst og triceps',
      'Ligg på ryggen med bøyde knær. Press manualene rett opp, senk til albuene berører matta.',
      'Lettere vekter', [
    _mat, Head(Offset(12, 47)), Line([Offset(17, 50), Offset(42, 50)]),
    Line([Offset(42, 50), Offset(50, 38), Offset(56, 52)]), Line([Offset(24, 50), Offset(24, 30)]),
    Db(Rect.fromLTWH(18, 24, 12, 6)),
  ]),
  'markløft': Exercise('markløft', 'Markløft med manualer', 'Hofte, sete og bakside lår',
      'Skyv hoftene bakover med rett rygg, manualene glir langs lårene. Reis deg ved å skyve hoftene frem.',
      'Kortere bevegelse, lettere vekt', [
    _floor, Head(Offset(24, 16)), Line([Offset(28, 20), Offset(44, 34)]),
    Line([Offset(44, 34), Offset(42, 60)]), Line([Offset(33, 25), Offset(35, 44)]),
    Db(Rect.fromLTWH(30, 44, 11, 6)),
  ]),
  'skulderpress': Exercise('skulderpress', 'Skulderpress', 'Skuldre og triceps',
      'Press manualene kontrollert over hodet uten å svaie i korsryggen.',
      'Sittende på stol, lettere vekt', [
    Prop([Offset(16, 61), Offset(56, 61)]), Head(Offset(36, 20)), Line([Offset(36, 25), Offset(36, 44)]),
    Line([Offset(30, 60), Offset(36, 44), Offset(42, 60)]),
    Line([Offset(26, 12), Offset(26, 24), Offset(36, 29), Offset(46, 24), Offset(46, 12)]),
    Db(Rect.fromLTWH(20, 6, 12, 6)), Db(Rect.fromLTWH(40, 6, 12, 6)),
  ]),
  'planke': Exercise('planke', 'Planke', 'Mage og kjerne',
      'Underarmene i matta, kroppen i en rett linje fra hode til hæl. Pust rolig.',
      'Knærne i matta', [
    _mat, Head(Offset(13, 37)), Line([Offset(18, 40), Offset(62, 50)]),
    Line([Offset(21, 41), Offset(21, 51), Offset(30, 51)]),
  ]),
  'armheving': Exercise('armheving', 'Armheving mot benk', 'Bryst, skuldre og armer',
      'Hendene på en stødig benk, kroppen rett. Senk brystet mot kanten og press opp.',
      'Mot vegg', [
    Prop([Offset(4, 61), Offset(68, 61)]),
    Prop([Offset(44, 40), Offset(66, 40)], width: 3), Prop([Offset(48, 40), Offset(48, 61)], width: 3),
    Prop([Offset(62, 40), Offset(62, 61)], width: 3),
    Head(Offset(43, 27)), Line([Offset(8, 60), Offset(38, 34)]), Line([Offset(38, 34), Offset(46, 40)]),
  ]),
  'utfall': Exercise('utfall', 'Utfall bakover', 'Lår, sete og balanse',
      'Ta et langt steg bakover og senk bakre kne mot gulvet. Skyv deg tilbake med fremre bein.',
      'Hold i en stol for støtte', [
    Prop([Offset(6, 61), Offset(66, 61)]), Head(Offset(34, 10)), Line([Offset(34, 15), Offset(34, 36)]),
    Line([Offset(34, 36), Offset(46, 46), Offset(46, 60)]), Line([Offset(34, 36), Offset(24, 52), Offset(12, 58)]),
    Line([Offset(34, 20), Offset(30, 34)]), Db(Rect.fromLTWH(27, 34, 6, 9)),
  ]),
  'deadbug': Exercise('deadbug', 'Dead bug', 'Mage og stabilitet',
      'Ligg på ryggen, armer og knær i 90 grader. Strekk motsatt arm og bein sakte ut, korsryggen mot matta.',
      'Strekk bare beina', [
    _mat, Head(Offset(10, 46)), Line([Offset(15, 48), Offset(40, 48)]),
    Line([Offset(22, 48), Offset(22, 28)]), Line([Offset(18, 48), Offset(6, 32)]),
    Line([Offset(40, 48), Offset(40, 34), Offset(54, 34)]), Line([Offset(40, 48), Offset(64, 44)]),
  ]),
  'sidesteg': Exercise('sidesteg', 'Raske sidesteg', 'Puls og bein',
      'Små, raske steg til siden og tilbake. Lett bøyde knær, ingen hopp.',
      'Rolige sidesteg', [
    _floor, Head(Offset(36, 10)), Line([Offset(36, 15), Offset(36, 36)]),
    Line([Offset(22, 60), Offset(36, 36), Offset(50, 60)]), Line([Offset(26, 30), Offset(36, 20), Offset(46, 30)]),
    Prop([Offset(6, 46), Offset(16, 46)], width: 3), Prop([Offset(56, 46), Offset(66, 46)], width: 3),
  ]),
  'stolknebøy': Exercise('stolknebøy', 'Knebøy til stol', 'Lår og sete',
      'Sett deg rolig ned på stolen og reis deg uten å bruke hendene.',
      'Bruk hendene til støtte', [
    _floor, Prop([Offset(46, 40), Offset(62, 40)], width: 3), Prop([Offset(48, 40), Offset(48, 61)], width: 3),
    Prop([Offset(62, 40), Offset(62, 61)], width: 3), Prop([Offset(62, 40), Offset(62, 18)], width: 3),
    Head(Offset(30, 12)), Line([Offset(31, 17), Offset(40, 36)]),
    Line([Offset(40, 36), Offset(24, 40), Offset(24, 60)]), Line([Offset(33, 24), Offset(18, 28)]),
  ]),
  'seteløft': Exercise('seteløft', 'Seteløft på matte', 'Sete og bakside lår',
      'Ligg på ryggen med bøyde knær. Løft hoften til kroppen er rett fra knær til skuldre.',
      'Mindre løft, hold kortere', [
    _mat, Head(Offset(10, 50)), Line([Offset(15, 52), Offset(24, 52), Offset(40, 38)]),
    Line([Offset(40, 38), Offset(52, 42), Offset(52, 55)]), Line([Offset(18, 53), Offset(30, 55)]),
  ]),
  'marsj': Exercise('marsj', 'Rask marsj med høye kneløft', 'Puls',
      'Marsjer raskt på stedet og løft knærne. Bruk armene aktivt.',
      'Lavere kneløft', [
    Prop([Offset(16, 61), Offset(56, 61)]), Head(Offset(36, 10)), Line([Offset(36, 15), Offset(36, 36)]),
    Line([Offset(36, 36), Offset(47, 42), Offset(45, 54)]), Line([Offset(36, 36), Offset(34, 60)]),
    Line([Offset(27, 31), Offset(36, 21), Offset(45, 27)]),
  ]),
  'bicepscurl': Exercise('bicepscurl', 'Bicepscurl', 'Armer',
      'Albuene inntil kroppen. Bøy armene og løft manualene rolig, senk kontrollert.',
      'Én arm om gangen', [
    Prop([Offset(16, 61), Offset(56, 61)]), Head(Offset(36, 10)), Line([Offset(36, 15), Offset(36, 38)]),
    Line([Offset(31, 60), Offset(36, 38), Offset(41, 60)]), Line([Offset(36, 20), Offset(40, 34), Offset(48, 26)]),
    Db(Rect.fromLTWH(45, 20, 6, 9)),
  ]),
  'balanse': Exercise('balanse', 'Balanse på ett bein', 'Balanse og ankler',
      'Stå på ett bein ved en stødig benk. Hold lett i benken ved behov. 2 × 30 sek per bein.',
      'Hold med begge hender', [
    _floor, Prop([Offset(46, 30), Offset(64, 30)], width: 3), Prop([Offset(50, 30), Offset(50, 61)], width: 3),
    Prop([Offset(62, 30), Offset(62, 61)], width: 3),
    Head(Offset(32, 10)), Line([Offset(32, 15), Offset(32, 36)]), Line([Offset(32, 36), Offset(32, 60)]),
    Line([Offset(32, 36), Offset(40, 46), Offset(36, 52)]), Line([Offset(32, 20), Offset(48, 30)]),
  ]),
  'sittendepress': Exercise('sittendepress', 'Skulderpress sittende', 'Skuldre og triceps',
      'Sitt godt på en stol med ryggen mot ryggstøtten. Press manualene rolig over hodet og senk til skulderhøyde.',
      'Én arm om gangen, lettere vekt', [
    _floor, Prop([Offset(34, 44), Offset(52, 44)], width: 3), Prop([Offset(36, 44), Offset(36, 61)], width: 3),
    Prop([Offset(50, 44), Offset(50, 61)], width: 3), Prop([Offset(52, 44), Offset(52, 24)], width: 3),
    Head(Offset(42, 14)), Line([Offset(42, 19), Offset(44, 42)]), Line([Offset(44, 42), Offset(28, 44), Offset(28, 60)]),
    Line([Offset(34, 8), Offset(34, 20), Offset(42, 25), Offset(50, 20), Offset(50, 8)]),
    Db(Rect.fromLTWH(28, 3, 12, 6)), Db(Rect.fromLTWH(44, 3, 12, 6)),
  ]),
  'veggarmheving': Exercise('veggarmheving', 'Armheving mot vegg', 'Bryst, skuldre og armer',
      'Stå en armlengde fra veggen med hendene i skulderhøyde. Bøy armene til nesen nærmer seg veggen, og press tilbake.',
      'Stå nærmere veggen', [
    _floor, Prop([Offset(60, 6), Offset(60, 61)], width: 4),
    Head(Offset(52, 18)), Line([Offset(30, 60), Offset(49, 24)]), Line([Offset(49, 26), Offset(58, 30)]),
  ]),
  'sideplanke': Exercise('sideplanke', 'Sideplanke på kne', 'Sidemage og hofte',
      'Ligg på siden med underarmen i matta og knærne bøyd. Løft hoften så kroppen blir rett fra kne til skulder.',
      'Hold kortere, 10–15 sek', [
    _mat, Head(Offset(14, 32)), Line([Offset(18, 36), Offset(42, 50)]), Line([Offset(42, 50), Offset(56, 54)]),
    Line([Offset(20, 37), Offset(20, 54)]), Line([Offset(20, 36), Offset(24, 22)]),
  ]),
  'stegopp': Exercise('stegopp', 'Steg opp på trapp', 'Lår, sete og balanse',
      'Sett hele foten på et trappetrinn og press deg opp. Gå rolig ned igjen. Bytt bein. Hold i rekkverket.',
      'Lavere trinn', [
    _floor, Prop([Offset(36, 46), Offset(62, 46)], width: 3), Prop([Offset(36, 46), Offset(36, 61)], width: 3),
    Head(Offset(42, 9)), Line([Offset(42, 14), Offset(42, 33)]), Line([Offset(42, 33), Offset(50, 39), Offset(50, 46)]),
    Line([Offset(42, 33), Offset(36, 47), Offset(30, 60)]), Line([Offset(42, 19), Offset(36, 31)]), Line([Offset(42, 19), Offset(48, 31)]),
  ]),
  'superman': Exercise('superman', 'Rygghev på matte', 'Rygg og sete',
      'Ligg på magen. Løft armer og bein litt fra matta samtidig, hold et sekund og senk rolig. Se ned i matta.',
      'Løft bare armene, eller bare beina', [
    _mat, Head(Offset(14, 44)), Line([Offset(19, 48), Offset(48, 52)]), Line([Offset(48, 52), Offset(64, 46)]),
    Line([Offset(18, 47), Offset(4, 40)]),
  ]),
  'veggengel': Exercise('veggengel', 'Veggengel', 'Skuldre og øvre rygg',
      'Stå med ryggen inntil en vegg, armene i W-form mot veggen. Skyv armene rolig opp til Y og ned igjen.',
      'Mindre bevegelse', [
    _floor, Head(Offset(36, 11)), Line([Offset(36, 16), Offset(36, 40)]), Line([Offset(30, 60), Offset(36, 40), Offset(42, 60)]),
    Line([Offset(22, 8), Offset(24, 24), Offset(36, 21), Offset(48, 24), Offset(50, 8)]),
  ]),
};

/// Alternativer brukeren kan bytte til (samme muskelgruppe).
const alternatives = <String, List<String>>{
  'knebøy': ['stolknebøy', 'stegopp', 'seteløft'],
  'stolknebøy': ['knebøy', 'seteløft'],
  'utfall': ['stegopp', 'stolknebøy', 'seteløft'],
  'stegopp': ['stolknebøy', 'seteløft'],
  'markløft': ['seteløft', 'superman'],
  'seteløft': ['stolknebøy', 'superman'],
  'roing': ['enarmsroing', 'superman'],
  'enarmsroing': ['roing', 'superman'],
  'brystpress': ['armheving', 'veggarmheving'],
  'armheving': ['veggarmheving', 'brystpress'],
  'skulderpress': ['sittendepress', 'veggengel'],
  'sittendepress': ['skulderpress', 'veggengel'],
  'planke': ['sideplanke', 'deadbug'],
  'deadbug': ['planke', 'sideplanke'],
  'marsj': ['sidesteg'],
  'sidesteg': ['marsj'],
};

/// Utstyr en øvelse krever.
const _needsDumbbells = {'roing', 'enarmsroing', 'brystpress', 'markløft', 'skulderpress', 'sittendepress', 'bicepscurl'};
const _needsBench = {'armheving', 'enarmsroing', 'stolknebøy', 'sittendepress'};

/// Erstatning når utstyret mangler.
const _fallback = <String, String>{
  'roing': 'superman',
  'enarmsroing': 'superman',
  'brystpress': 'armheving',
  'armheving': 'veggarmheving',
  'markløft': 'seteløft',
  'skulderpress': 'veggengel',
  'sittendepress': 'veggengel',
  'bicepscurl': 'veggarmheving',
  'stolknebøy': 'knebøy',
};

bool _hasGear(String id, Profile? p) {
  if (p == null) return true;
  if (_needsDumbbells.contains(id) && !p.has(Activity.manualer)) return false;
  if (_needsBench.contains(id) && !p.has(Activity.benk)) return false;
  return true;
}

/// Øvelsen som faktisk brukes: brukerens eget bytte, deretter erstatning hvis utstyret mangler.
String resolveExercise(String id, {Profile? profile, Map<String, String> swaps = const {}}) {
  var x = swaps[id] ?? id;
  for (var i = 0; i < 4 && !_hasGear(x, profile); i++) {
    x = _fallback[x] ?? x;
  }
  return x;
}

/// Alternativer som passer utstyret.
List<String> alternativesFor(String original, {Profile? profile}) => [
      original,
      ...?alternatives[original],
    ].where((x) => _hasGear(x, profile)).toList();

const strengthA = ['knebøy', 'roing', 'brystpress', 'markløft', 'skulderpress', 'planke'];
const circuits = {
  1: ['knebøy', 'armheving', 'roing', 'planke', 'marsj'],
  2: ['utfall', 'markløft', 'skulderpress', 'deadbug', 'sidesteg'],
  3: ['stolknebøy', 'brystpress', 'enarmsroing', 'seteløft', 'marsj'],
};

/// Øvelsene i planen for økta, før bytte.
List<String> baseExercisesFor(Session s) => s.circuit == 0 ? strengthA : (circuits[s.circuit] ?? circuits[1]!);

/// Øvelsene brukeren faktisk gjør (med bytte og utstyr).
List<String> exercisesFor(Session s, {Profile? profile, Map<String, String> swaps = const {}}) =>
    [for (final id in baseExercisesFor(s)) resolveExercise(id, profile: profile, swaps: swaps)];

/// Repetisjoner/tid for Styrke A ut fra antall runder.
String repsFor(String id, Session s) {
  final heavy = s.rounds >= 3;
  if (id == 'planke') return heavy ? '30–45 sek' : '20–30 sek';
  if (id == 'sideplanke') return heavy ? '20–30 sek per side' : '15–20 sek per side';
  if (id == 'stegopp' || id == 'utfall') return heavy ? '8–10 per bein' : '6–8 per bein';
  return heavy ? '12–15 repetisjoner' : '10–12 repetisjoner';
}

class FigurePainter extends CustomPainter {
  final List<Prim> figure;
  final Color color;
  final Color accent;
  final Color prop;

  FigurePainter(this.figure, {required this.color, required this.accent, required this.prop});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 72;
    canvas.save();
    canvas.translate((size.width - 72 * s) / 2, (size.height - 72 * s) / 2);
    canvas.scale(s);
    final body = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final p in figure) {
      switch (p) {
        case Prop(:final pts, :final width):
          final paint = Paint()
            ..color = prop
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round;
          canvas.drawPath(_path(pts), paint);
        case Line(:final pts):
          canvas.drawPath(_path(pts), body);
        case Head(:final c):
          canvas.drawCircle(c, 5, body);
        case Db(:final r):
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(2)), Paint()..color = accent);
      }
    }
    canvas.restore();
  }

  Path _path(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(FigurePainter old) => old.figure != figure;
}

/// Illustrasjon i en avrundet flis.
class ExerciseFigure extends StatelessWidget {
  final String id;
  final double size;
  const ExerciseFigure(this.id, {super.key, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final ex = exercises[id]!;
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Illustrasjon: ${ex.name}',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(size / 5)),
        padding: EdgeInsets.all(size * 0.06),
        child: CustomPaint(
          painter: FigurePainter(ex.figure,
              color: cs.onPrimaryContainer, accent: const Color(0xFFC2581B), prop: const Color(0xFF9DB5A8)),
        ),
      ),
    );
  }
}
