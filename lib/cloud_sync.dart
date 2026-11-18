// Lagring i Supabase: innlogging med e-post og passord, og automatisk opplasting.
// Appen virker fortsatt uten nett. Data på telefonen er hovedkilden, og skyen
// er en kopi som kan hentes ned på en ny telefon.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import 'config.dart';
import 'models.dart';
import 'state.dart';

enum CloudChoice { brukSky, brukTelefon }

class CloudSync extends ChangeNotifier {
  CloudSync._();
  static final instance = CloudSync._();

  bool _ready = false;
  Timer? _debounce;
  bool syncing = false;
  DateTime? lastUpload;
  String? lastError;
  AppState? _app;

  SupabaseClient get _db => Supabase.instance.client;
  User? get user => _ready ? _db.auth.currentUser : null;
  bool get loggedIn => user != null;

  Future<void> init(AppState app) async {
    _app = app;
    try {
      await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
      _ready = true;
    } catch (e) {
      lastError = 'Kunne ikke starte skylagring: $e';
    }
    app.onChanged = _scheduleUpload;
    notifyListeners();
  }

  void _scheduleUpload() {
    if (!loggedIn) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () => upload());
  }

  // ---------- Innlogging ----------

  /// Returnerer true hvis brukeren er logget inn med en gang
  /// (false betyr at e-posten må bekreftes først).
  Future<bool> signUp(String email, String password) async {
    final r = await _db.auth.signUp(email: email.trim(), password: password);
    notifyListeners();
    return r.session != null;
  }

  Future<void> signIn(String email, String password) async {
    await _db.auth.signInWithPassword(email: email.trim(), password: password);
    notifyListeners();
  }

  Future<void> resetPassword(String email) => _db.auth.resetPasswordForEmail(email.trim());

  Future<void> signOut() async {
    _debounce?.cancel();
    await _db.auth.signOut();
    notifyListeners();
  }

  // ---------- Synk ----------

  /// Hent det som ligger i skyen for denne brukeren (eller null).
  Future<({Map<String, dynamic> data, DateTime updatedAt})?> fetchRemote() async {
    final row = await _db.from('app_state').select('data, updated_at').eq('user_id', user!.id).maybeSingle();
    if (row == null) return null;
    return (data: row['data'] as Map<String, dynamic>, updatedAt: DateTime.parse(row['updated_at'] as String));
  }

  /// Etter innlogging: avgjør om skyen eller telefonen skal brukes.
  /// [ask] kalles bare når begge har en plan og de er ulike.
  Future<String> afterLogin(Future<CloudChoice?> Function(DateTime remote, DateTime? local) ask) async {
    final app = _app!;
    final remote = await fetchRemote();
    if (remote == null) {
      if (app.profile != null) {
        await upload();
        return 'Dataene på telefonen er lagret i skyen.';
      }
      return 'Logget inn. Lag en plan, så lagres den i skyen.';
    }
    if (app.profile == null) {
      await app.replaceWith(remote.data);
      return 'Planen og øktene dine er hentet fra skyen.';
    }
    final choice = await ask(remote.updatedAt, app.modifiedAt);
    if (choice == CloudChoice.brukSky) {
      await app.replaceWith(remote.data);
      return 'Data fra skyen er tatt i bruk.';
    }
    if (choice == CloudChoice.brukTelefon) {
      await upload();
      return 'Dataene på telefonen er lagret i skyen.';
    }
    return 'Logget inn.';
  }

  /// Last opp hele tilstanden, pluss økter og målinger i egne tabeller.
  Future<void> upload() async {
    final app = _app;
    final u = user;
    // Ingen plan (f.eks. rett etter «Start helt på nytt»): ikke overskriv skyen med tomme data.
    if (app == null || u == null || syncing || app.profile == null) return;
    syncing = true;
    notifyListeners();
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _db.from('app_state').upsert({
        'user_id': u.id,
        'data': app.toJson(),
        'app_version': appVersion,
        'updated_at': now,
      });
      final sessions = [
        for (final w in app.weeks)
          for (final s in w.sessions) sessionRow(u.id, s, now)
      ];
      await _db.from('okter').delete().eq('user_id', u.id);
      if (sessions.isNotEmpty) await _db.from('okter').insert(sessions);
      final ms = [
        for (final m in app.measurements)
          {
            'user_id': u.id,
            'dato': _d(m.date),
            'vekt_kg': m.weightKg,
            'midje_cm': m.waistCm,
            'updated_at': now,
          }
      ];
      await _db.from('malinger').delete().eq('user_id', u.id);
      if (ms.isNotEmpty) await _db.from('malinger').insert(ms);
      lastUpload = DateTime.now();
      lastError = null;
    } catch (e) {
      lastError = 'Kunne ikke lagre i skyen (prøver igjen ved neste endring): $e';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }
}

String _d(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

@visibleForTesting
Map<String, dynamic> sessionRow(String userId, Session s, String now) => {
      'user_id': userId,
      'id': s.id,
      'dato': _d(s.date),
      'type': s.type.name,
      'tittel': s.title,
      'minutter': s.minutes,
      'anstrengelse': s.effort.name,
      'status': s.status.name,
      'ekstra': s.extra,
      'handtert': s.resolution?.name,
      'notat': s.note,
      'updated_at': now,
    };
