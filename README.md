# Treningsplan – Flutter-app for Android og iOS

Personlig treningsprogram fra startdato til måldato: styrke med manualer hjemme,
CrossFit-inspirerte sirkler, rask gange, jogging og motbakkeintervaller ute.
Hvis du står over en økt, foreslår appen hvordan du tar den igjen.

## Det appen gjør (første versjon)

- **Oppsett:** alder, høyde, vekt, målvekt, start- og måldato, form, intensitet
  (rolig/moderat/krevende), dager per uke (3–6), lengde per økt og hvilke aktiviteter du liker.
  Appen varsler hvis vektmålet krever mer enn ca. 1 % av kroppsvekten per uke,
  og ved helseforbehold anbefaler den å snakke med fastlegen først.
- **Plangenerator:** faser (tilvenning, oppbygging, kapasitet, vedlikehold, testuke),
  lettuke hver 4. uke, maks 10 % økning i belastning per uke, og aldri harde økter
  to dager på rad. Intervallene går fra 4 × 1 min til 5 × 4 min. Torsdagene roterer mellom tre sirkler.
- **Øvelser med illustrasjoner:** 16 øvelser med tegnede figurer, instruksjon og en lettere variant.
- **Guidet økt:** klokka starter automatisk med 10 sekunder «gjør deg klar», og går gjennom
  oppvarming, sett, intervaller og pauser etter planlagt tid. Styrke A er også tidsstyrt
  (40–50 sek per sett, 60 sek pause). Tiden blir riktig også hvis appen har vært i bakgrunnen.
  Skjermen holdes på under økta.
- **Stemmesignal (norsk tale):** sier type økt, «Start økt», hver øvelse med mål («Start. Knebøy
  med manual. 12 til 15 repetisjoner»), «Pause. Hvil i 60 sekunder. Neste: …», og teller ned
  «tre, to, en» før hvert bytte. Kan slås av i økta.
- **Musikk:** appens egne treningslåter i fem typer – rolig, piano, rock, pop og klassisk – med
  en energisk låt under arbeid og en rolig i pausene (dempes når stemmen snakker). Eller egen musikk
  fra Spotify o.l. (dempes kort når stemmen snakker), eller ingen musikk. Velges under Profil →
  Lyd og musikk (med prøvelytting) eller med notetegnet underveis i økta. Låtene er egne
  komposisjoner laget av `tools/lag_musikk.py` og har ingen opphavsrett.
- **Tapt økt:** økter som ikke er krysset av innen dagen er over, regnes som stått over. Du kan da velge å
  - *flytte* økta til en ledig dag samme uke (intervaller legges aldri inntil en annen hard økt),
  - *fordele* den på neste uke – bare for tapte økter siste 7 dager, aldri inn i en lettuke eller en uke som
    har startet, og innenfor det som er igjen av 10 %-grensen (felles for alle fordelinger), eller
  - *stryke* den, slik at neste uke holdes på samme nivå (maks ett steg ned per uke).
  Valget kan angres. Står du over 3 økter på 2 uker, settes planen ett steg ned – før forslagene vises,
  med en forklaring. Tapte økter eldre enn 14 dager lukkes.
- **Fravær (sykdom, ferie, skade):** registreres bakover eller frem i tid. Økter i perioden teller ikke som
  tapt. Etter minst en uke starter planen med en lettere uke og et lavere nivå (1–2 uker: ett steg,
  2–4 uker: to, 4–6 uker: tre, over 6 uker: fra start). Måldatoen kan flyttes like mange uker. Har du vært
  borte en stund uten å registrere det, foreslår appen fravær samlet i stedet for mange varsler.
  «Tilbake nå» avslutter fraværet før tiden.
- **Start planen i dag:** før startdatoen vises en knapp som flytter starten til i dag (mål og måldato beholdes).
- **Egne treningsdager:** velg 3–6 ukedager. Intervallene legges der du har hviledag etter, langturen i helga.
- **Flytte eller bytte en økt** med en annen dag i samme uke (dager som ville gitt harde økter på rad er sperret).
- **Gjør lettere i dag:** kortere økt eller bytt til rolig tur – bare nedover, alltid trygt.
- **Bytt øvelse** ved vondt kne, skulder eller rygg (gjelder alle kommende økter). Uten manualer eller
  stol/benk velges kroppsvektøvelser automatisk.
- **Vekter og repetisjoner** per øvelse etter styrkeøkter, med utvikling under Fremgang.
- **Rette registreringer:** faktisk varighet, anstrengelse og følelse; type for ekstraøkter.
- **Egen makspuls** (eller «medisin påvirker pulsen») brukes når klokka bedømmer anstrengelse.
- **Lengre pauser** (+15/30/60 sek) i guidede økter.
- **Det klokka registrerte:** under økta (og i lista under Samsung-klokke) vises tid, varighet, distanse, tempo,
  skritt, snitt-/høyeste/laveste puls, kalorier, tid i pulssoner og pulskurve – og en sammenligning med planen
  (tid og pulsmål for økttypen). Klokkeøkter de siste 30 dagene hentes, også før planen starter.
- **Turøkter med nedtelling og stemme:** beskjed etter en firedel, halvveis, tre firedeler og 5 min før slutt,
  og «tre, to, en» på slutten. Appen holdes i gang med et varsel (forgrunnstjeneste på Android) slik at du kan
  låse skjermen og høre på radio, podkast eller Spotify – lyden dempes kort når stemmen snakker.
- **Forklaring** på planskjermen hver gang planen gjøres lettere eller tyngre, og hvorfor.
- **Mål:** gå ned i vekt, eller holde vekten / bedre form. Planen er maks 104 uker (to år).
- **Ekstra økter utenom planen:** registreres i dag eller tilbake i tid (gange, jogging, intervaller,
  styrke, sykling, ski, annet), med varighet og anstrengelse. De regnes med i ukas trening.
  En ekstra økt av samme slag (kondisjon/styrke) på minst 70 % av tiden tar automatisk igjen en
  tapt økt i samme uke eller inntil 7 dager etter. Intervaller kan ikke tas igjen med en rolig tur.
- **Ikke gjennomført innen datoen = ikke utført.** En planlagt økt kan bare etterregistreres på sin
  egen dato (du gjorde den, men glemte å krysse av). Trente du en annen dag, registreres det som ekstra økt.
- **Juster mål underveis:** målvekt, måldato, intensitet, treningsdager, utstyr og makspuls. Ukene som
  er gjennomført eller pågår beholdes som de er. Mer trening trappes opp: de nye ukene starter på et
  lavere nivå slik at økningen aldri blir mer enn 10 % per uke, og appen sier fra når alle dagene er med.
- **Målinger** valideres (35–250 kg, 40–200 cm midje), kan registreres på valgfri dato og rettes eller slettes.
- **Start helt på nytt:** valgfritt å beholde vektmålinger og tester.
- **Samsung-klokke (Galaxy Watch):** økter hentes automatisk fra Samsung Health via Health Connect
  når appen åpnes. En økt samme dag og av samme slag som den planlagte krysser av den planlagte
  (intervaller gjenkjennes på høy makspuls). Andre økter blir ekstra økter og kan ta igjen tapte.
  Vekt fra smartvekt hentes også. Oppsett: Samsung Health → Innstillinger → Health Connect →
  tillat deling av Trening, Puls og Vekt. Deretter Profil → Samsung-klokke → Koble til.
- **Tilpasning:** «For lett / Passe / For tungt» etter hver økt. To like svar på rad
  justerer nivået for kommende uker.
- **Fremgang:** vektkurve mot plan, midjemål, tester (knebøy, planke, 3 km, pust i bakke) og
  kostholdsmål (kaloriunderskudd).
- Alt lagres på telefonen og virker uten nett.
- **Lagring i skyen (Supabase):** med konto (e-post og passord) lastes plan, økter og målinger opp
  automatisk etter hver endring. På en ny telefon logger du inn og henter alt ned igjen.
  Hver bruker ser bare sine egne data (radregler i databasen).

## Kjøre appen

Krever [Flutter](https://docs.flutter.dev/get-started/install) 3.50 eller nyere.

```bash
flutter pub get
flutter test          # 100 tester, blant annet trygghetsregler i test/kontroll_test.dart: plan, tapt økt, ekstra økter, etterregistrering, justering, klokke-import
flutter run           # på tilkoblet telefon eller emulator
```

### Android
```bash
flutter build apk --release
# Filen havner i build/app/outputs/flutter-apk/app-release.apk
```
Til Google Play: lag en egen signeringsnøkkel (se Flutter-dokumentasjonen «Build and release an Android app»)
og bygg med `flutter build appbundle`.

### iPhone
iOS-appen må bygges på en Mac med Xcode:
```bash
flutter build ios --release
open ios/Runner.xcworkspace   # velg Team under Signing, og kjør på telefonen
```
For å legge den ut i App Store eller TestFlight trengs en Apple Developer-konto.

## Supabase

Prosjekt: `treningsplan` (EU, Irland) – https://vyuhelgajlsjdcukyusw.supabase.co

| Tabell | Innhold |
|---|---|
| `app_state` | Hele app-tilstanden som JSON, én rad per bruker |
| `okter` | Alle økter (planlagte og ekstra) med dato, type, minutter, status |
| `malinger` | Vekt og midjemål per dag |

Databaseoppsettet ligger i `supabase/migrations/`. Adresse og publiserbar nøkkel ligger i
`lib/config.dart` (nøkkelen er laget for å ligge i appen; tilgangen styres av radreglene).

Nye kontoer bekreftes automatisk av en databaseregel (`auto_confirm_email` på `auth.users`),
så man er innlogget med en gang etter registrering. Supabase sender likevel en bekreftelses-e-post;
den kan ignoreres. Vil du heller slå av e-posten helt: Authentication → Sign In / Providers →
Email → slå av «Confirm email».

## Trygghetsregler (testes i `test/kontroll_test.dart`)

- Planlagt belastning i en uke er maks 10 % over forrige vanlige uke (ekstraøkter telles ikke).
- Lettuker er maks 90 % av forrige vanlige uke.
- Aldri harde økter to dager på rad.
- Endringer (fordel, «for lett», justering, fravær) kontrolleres med `safetyViolations` i tester.

## Struktur

| Fil | Innhold |
|---|---|
| `lib/models.dart` | Profil, økt, uke, målinger, norsk datoformat |
| `lib/plan_generator.dart` | Bygger planen: faser, lettuker, egne treningsdager, 10 %-grense (`enforceLoadCap`, `safetyViolations`), intervallstige |
| `lib/compensation.dart` | Forslag ved tapt økt: flytt, fordel, stryk – og angre |
| `lib/move.dart` | Flytte/bytte økter innen uka uten harde økter på rad |
| `lib/exercises.dart` | Øvelsesbibliotek og tegnede figurer |
| `lib/workout_steps.dart` | Gjør en økt om til steg for timeren, med tekst som leses opp |
| `lib/coach.dart` | Stemme (flutter_tts), musikk (just_audio) og våken skjerm |
| `assets/musikk/`, `tools/lag_musikk.py` | Appens egne treningslåter (`<type>_arbeid.mp3`, `<type>_pause.mp3`) og skriptet som lager dem |
| `lib/screens/sound_screen.dart` | Valg av stemme, musikkilde og musikktype, med prøvelytting |
| `lib/watch_import.dart` | Kobler økter fra klokka til planen, anstrengelse fra puls |
| `lib/health_sync.dart` | Henter fra Health Connect (pakken `health`) |
| `lib/cloud_sync.dart` | Innlogging og opplasting til Supabase |
| `lib/state.dart` | Tilstand, lagring, tilbakesteg og tilpasning |
| `lib/screens/` | Oppsett/justering, ukeplan, økt, guidet timer, tapt økt, ekstra økt, fremgang, profil |

## Neste steg

- Påminnelser (`flutter_local_notifications`)
- Holde skjermen våken under økta (`wakelock_plus`)
- GPS for tid og distanse ute (`geolocator`)
- Animerte øvelsesfigurer eller korte videoer

Merk: Flutter 3.50 markerer `package:flutter/material.dart` som utfaset til fordel for
`material_ui`. Det gir bare informasjonsmeldinger i `flutter analyze` og virker som normalt.
