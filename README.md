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
  - *fordele* den på neste uke innenfor 10 %-grensen, eller
  - *stryke* den, slik at neste uke holdes på samme nivå.
  Står du over 3 økter på 2 uker, går progresjonen én uke tilbake.
- **Ekstra økter utenom planen:** registreres i dag eller tilbake i tid (gange, jogging, intervaller,
  styrke, sykling, ski, annet), med varighet og anstrengelse. De regnes med i ukas trening.
  En ekstra økt av samme slag (kondisjon/styrke) på minst 70 % av tiden tar automatisk igjen en
  tapt økt i samme uke eller inntil 7 dager etter. Intervaller kan ikke tas igjen med en rolig tur.
- **Ikke gjennomført innen datoen = ikke utført.** En planlagt økt kan bare etterregistreres på sin
  egen dato (du gjorde den, men glemte å krysse av). Trente du en annen dag, registreres det som ekstra økt.
- **Juster mål underveis:** målvekt, måldato, intensitet, dager per uke og aktiviteter. Ukene som
  er gjennomført eller pågår beholdes som de er, og kommende uker bygges på nytt fra nivået du er på.
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
flutter test          # 67 tester: plan, tapt økt, ekstra økter, etterregistrering, justering, klokke-import
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

## Struktur

| Fil | Innhold |
|---|---|
| `lib/models.dart` | Profil, økt, uke, målinger, norsk datoformat |
| `lib/plan_generator.dart` | Bygger planen: faser, lettuker, 10 %-grense, intervallstige |
| `lib/compensation.dart` | Forslag ved tapt økt: flytt, fordel, stryk |
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
