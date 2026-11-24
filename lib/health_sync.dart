// Henter økter, puls og vekt fra Health Connect (Android).
// Samsung Health deler data fra Galaxy Watch hit når deling er slått på.

import 'dart:io';

import 'package:health/health.dart';

import 'models.dart';
import 'state.dart';
import 'watch_import.dart';

enum WatchStatus { ikkeStottet, maaInstalleres, maaOppdateres, klar }

class HealthSync {
  HealthSync._();
  static final instance = HealthSync._();

  final _health = Health();
  bool _configured = false;
  DateTime? _lastAutoSync;

  /// Datatyper som må leses. Avstand, kalorier og skritt hentes sammen med øktene.
  static const _types = [
    HealthDataType.WORKOUT,
    HealthDataType.HEART_RATE,
    HealthDataType.WEIGHT,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.STEPS,
  ];

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  Future<WatchStatus> status() async {
    if (!Platform.isAndroid) return WatchStatus.ikkeStottet;
    try {
      await _configure();
      final s = await _health.getHealthConnectSdkStatus();
      return switch (s) {
        HealthConnectSdkStatus.sdkAvailable => WatchStatus.klar,
        HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired => WatchStatus.maaOppdateres,
        _ => WatchStatus.maaInstalleres,
      };
    } catch (_) {
      return WatchStatus.ikkeStottet;
    }
  }

  Future<void> installHealthConnect() => _health.installHealthConnect();

  /// Ber om lesetilgang. Returnerer true hvis øktene kan leses.
  Future<bool> connect() async {
    await _configure();
    final ok = await _health.requestAuthorization(
      _types,
      permissions: List.filled(_types.length, HealthDataAccess.READ),
    );
    if (!ok) return false;
    // Uten dette kan bare de siste 30 dagene leses. Ikke kritisk om brukeren sier nei.
    try {
      if (!await _health.isHealthDataHistoryAuthorized()) {
        await _health.requestHealthDataHistoryAuthorization();
      }
    } catch (_) {}
    return true;
  }

  Future<bool> hasAccess() async {
    try {
      await _configure();
      return await _health.hasPermissions([HealthDataType.WORKOUT], permissions: [HealthDataAccess.READ]) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Automatisk henting ved oppstart og når appen åpnes igjen (maks hvert 10. minutt).
  Future<ImportResult?> autoSync(AppState app, {bool force = false}) async {
    if (!app.watchSync || !Platform.isAndroid) return null;
    final now = DateTime.now();
    if (!force && _lastAutoSync != null && now.difference(_lastAutoSync!).inMinutes < 10) return null;
    _lastAutoSync = now;
    try {
      if (!await hasAccess()) return null;
      return await sync(app);
    } catch (_) {
      return null;
    }
  }

  /// Feilsøking: hva Health Connect gir appen de siste [days] dagene, og fra hvilke kilder.
  Future<String> diagnose(AppState app, {int days = 3}) async {
    final out = StringBuffer();
    final now = DateTime.now();
    final from = now.subtract(Duration(days: days));
    out.writeln('Status: ${await status()}');
    out.writeln('Henting slått på i appen: ${app.watchSync ? 'ja' : 'NEI'}');
    out.writeln('Sist hentet: ${app.lastWatchSync ?? 'aldri'}');
    out.writeln('Økter fra klokka lagret: ${app.watchLog.length}');
    try {
      await _configure();
      for (final t in _types) {
        bool? ok;
        try {
          ok = await _health.hasPermissions([t], permissions: [HealthDataAccess.READ]);
        } catch (e) {
          ok = null;
        }
        out.writeln('Tilgang ${t.name}: ${ok == true ? 'ja' : ok == false ? 'NEI' : 'ukjent'}');
      }
    } catch (e) {
      out.writeln('Tilgangssjekk feilet: $e');
    }
    out.writeln('');
    out.writeln('Siste $days dager i Health Connect:');
    for (final t in [HealthDataType.WORKOUT, HealthDataType.HEART_RATE, HealthDataType.STEPS]) {
      try {
        final pts = await _health.getHealthDataFromTypes(types: [t], startTime: from, endTime: now);
        final sources = <String, int>{};
        for (final p in pts) {
          sources[p.sourceName] = (sources[p.sourceName] ?? 0) + 1;
        }
        out.writeln('${t.name}: ${pts.length} '
            '${sources.isEmpty ? '' : '(${sources.entries.map((e) => '${e.key}: ${e.value}').join(', ')})'}');
        if (t == HealthDataType.WORKOUT) {
          for (final p in pts) {
            final v = p.value;
            final type = v is WorkoutHealthValue ? v.workoutActivityType.name : '?';
            out.writeln('  • ${fmtDato(p.dateFrom)} kl. ${fmtKl(p.dateFrom)}–${fmtKl(p.dateTo)} '
                '$type (${p.sourceName})${app.importedWorkoutIds.contains(p.uuid) ? ' – hentet' : ''}');
          }
        }
      } catch (e) {
        out.writeln('${t.name}: FEIL $e');
      }
    }
    return out.toString();
  }

  /// Hent nye økter siden sist (med to dagers overlapp) og legg dem inn i planen.
  Future<ImportResult> sync(AppState app) async {
    await _configure();
    final now = DateTime.now();
    // Første gang (eller før detaljene ble lagret): hent siste 30 dager, også før planen startet,
    // så det klokka registrerte kan vises.
    var from = app.watchLog.isEmpty || app.lastWatchSync == null
        ? now.subtract(const Duration(days: 30))
        : app.lastWatchSync!.subtract(const Duration(days: 2));
    if (now.difference(from).inDays > 60) from = now.subtract(const Duration(days: 60));

    final workoutsRaw = await _health.getHealthDataFromTypes(
      types: [HealthDataType.WORKOUT],
      startTime: from,
      endTime: now,
    );
    List<HealthDataPoint> hr = [];
    try {
      hr = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE],
        startTime: from,
        endTime: now,
      );
    } catch (_) {}
    List<HealthDataPoint> steps = [];
    List<HealthDataPoint> dist = [];
    try {
      steps = await _health.getHealthDataFromTypes(types: [HealthDataType.STEPS], startTime: from, endTime: now);
    } catch (_) {}
    try {
      dist = await _health.getHealthDataFromTypes(types: [HealthDataType.DISTANCE_DELTA], startTime: from, endTime: now);
    } catch (_) {}
    List<HealthDataPoint> cal = [];
    try {
      cal = await _health.getHealthDataFromTypes(
          types: [HealthDataType.TOTAL_CALORIES_BURNED], startTime: from, endTime: now);
    } catch (_) {}
    List<Delta> deltas(List<HealthDataPoint> pts) => [
          for (final x in pts)
            if (x.value is NumericHealthValue)
              (x.dateFrom, x.dateTo, (x.value as NumericHealthValue).numericValue.toDouble(), x.sourceName)
        ];
    final stepD = deltas(steps), distD = deltas(dist), calD = deltas(cal);
    List<HealthDataPoint> weightRaw = [];
    try {
      weightRaw = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WEIGHT],
        startTime: from,
        endTime: now,
      );
    } catch (_) {}

    final workouts = <ImportedWorkout>[];
    for (final d in workoutsRaw) {
      final v = d.value;
      if (v is! WorkoutHealthValue) continue;
      final hrIn = [
        for (final h in hr)
          if (!h.dateFrom.isBefore(d.dateFrom) && !h.dateFrom.isAfter(d.dateTo) && h.value is NumericHealthValue) h
      ];
      // Puls fra samme kilde som økta hvis den finnes (unngår dobbel puls fra flere apper).
      final sameSrc = hrIn.where((h) => h.sourceName == d.sourceName).toList();
      final samples = [
        for (final h in sameSrc.isNotEmpty ? sameSrc : hrIn)
          (h.dateFrom, (h.value as NumericHealthValue).numericValue.toDouble())
      ];
      final pulses = samples.map((x) => x.$2).where((x) => x > 30 && x < 230).toList();
      workouts.add(ImportedWorkout(
        id: d.uuid,
        start: d.dateFrom,
        end: d.dateTo,
        activity: mapActivity(v.workoutActivityType),
        avgHr: pulses.isEmpty ? null : pulses.reduce((a, b) => a + b) / pulses.length,
        maxHr: pulses.isEmpty ? null : pulses.reduce((a, b) => a > b ? a : b),
        // Pakkens egne totaler summerer alle kilder (telefon + Samsung = dobbelt), så vi regner selv
        // og bruker dem bare når vi ikke finner noe.
        kcal: sumOneSource(calD, d.dateFrom, d.dateTo, prefer: d.sourceName) ?? v.totalEnergyBurned,
        distanceM: sumOneSource(distD, d.dateFrom, d.dateTo, prefer: d.sourceName) ?? v.totalDistance,
        steps: sumOneSource(stepD, d.dateFrom, d.dateTo, prefer: d.sourceName) ?? v.totalSteps,
        source: d.sourceName,
        hrSamples: samples,
      ));
    }
    final weights = [
      for (final w in weightRaw)
        if (w.value is NumericHealthValue) (w.dateFrom, (w.value as NumericHealthValue).numericValue.toDouble())
    ];
    return app.importFromWatch(workouts, weights: weights);
  }
}

WatchActivity mapActivity(HealthWorkoutActivityType t) {
  switch (t) {
    case HealthWorkoutActivityType.WALKING:
    case HealthWorkoutActivityType.WALKING_TREADMILL:
    case HealthWorkoutActivityType.HIKING:
    case HealthWorkoutActivityType.STAIRS:
    case HealthWorkoutActivityType.STAIR_CLIMBING:
    case HealthWorkoutActivityType.SNOWSHOEING:
      return WatchActivity.gange;
    case HealthWorkoutActivityType.RUNNING:
    case HealthWorkoutActivityType.RUNNING_TREADMILL:
    case HealthWorkoutActivityType.TRACK_AND_FIELD:
      return WatchActivity.lop;
    case HealthWorkoutActivityType.BIKING:
    case HealthWorkoutActivityType.BIKING_STATIONARY:
    case HealthWorkoutActivityType.HAND_CYCLING:
      return WatchActivity.sykling;
    case HealthWorkoutActivityType.CROSS_COUNTRY_SKIING:
    case HealthWorkoutActivityType.SKIING:
    case HealthWorkoutActivityType.DOWNHILL_SKIING:
      return WatchActivity.ski;
    case HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING:
      return WatchActivity.intervall;
    case HealthWorkoutActivityType.STRENGTH_TRAINING:
    case HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING:
    case HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING:
    case HealthWorkoutActivityType.WEIGHTLIFTING:
    case HealthWorkoutActivityType.CALISTHENICS:
    case HealthWorkoutActivityType.CORE_TRAINING:
    case HealthWorkoutActivityType.CROSS_TRAINING:
      return WatchActivity.styrke;
    case HealthWorkoutActivityType.ELLIPTICAL:
    case HealthWorkoutActivityType.ROWING:
    case HealthWorkoutActivityType.ROWING_MACHINE:
    case HealthWorkoutActivityType.STAIR_CLIMBING_MACHINE:
    case HealthWorkoutActivityType.MIXED_CARDIO:
    case HealthWorkoutActivityType.SWIMMING:
    case HealthWorkoutActivityType.SWIMMING_POOL:
    case HealthWorkoutActivityType.SWIMMING_OPEN_WATER:
    case HealthWorkoutActivityType.JUMP_ROPE:
    case HealthWorkoutActivityType.STEP_TRAINING:
      return WatchActivity.kondisjon;
    default:
      return WatchActivity.annet;
  }
}

String fmtTid(DateTime t) =>
    '${fmtDato(t)} kl. ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
