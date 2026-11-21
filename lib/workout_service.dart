// Holder appen i gang under en guidet økt selv om skjermen er av eller du bruker
// radio, podkast eller Spotify i en annen app (Android: forgrunnstjeneste med varsel).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class WorkoutService {
  static bool _inited = false;
  static bool _running = false;

  static Future<void> start(String title, String text) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      if (!_inited) {
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'okt',
            channelName: 'Pågående økt',
            channelDescription: 'Viser tid igjen mens en økt pågår',
            onlyAlertOnce: true,
          ),
          iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
          foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.nothing(),
            allowWakeLock: true,
            allowAutoRestart: false,
            stopWithTask: true,
          ),
        );
        _inited = true;
      }
      if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
      final r = await FlutterForegroundTask.startService(
        serviceId: 4711,
        serviceTypes: [ForegroundServiceTypes.mediaPlayback],
        notificationTitle: title,
        notificationText: text,
      );
      _running = r is ServiceRequestSuccess;
    } catch (e) {
      debugPrint('Kunne ikke starte økt-tjenesten: $e');
    }
  }

  static Future<void> update(String text) async {
    if (!_running) return;
    try {
      await FlutterForegroundTask.updateService(notificationText: text);
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }
}
