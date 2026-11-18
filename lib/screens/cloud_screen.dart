import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../cloud_sync.dart';
import '../health_sync.dart' show fmtTid;
import '../main.dart';
import '../widgets.dart';

class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key});

  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _newUser = false;
  bool _busy = false;
  String? _message;

  CloudSync get _cloud => CloudSync.instance;

  @override
  void initState() {
    super.initState();
    _cloud.addListener(_update);
  }

  @override
  void dispose() {
    _cloud.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  String _norsk(Object e) {
    final m = e is AuthException ? e.message : e.toString();
    if (m.contains('Invalid login credentials')) return 'Feil e-post eller passord.';
    if (m.contains('Email not confirmed')) return 'E-posten er ikke bekreftet ennå. Trykk på lenken i e-posten fra Supabase.';
    if (m.contains('already registered')) return 'Det finnes allerede en konto med denne e-posten. Logg inn i stedet.';
    if (m.contains('Password should be')) return 'Passordet må ha minst 6 tegn.';
    if (m.contains('SocketException') || m.contains('Failed host lookup')) return 'Ingen nettforbindelse.';
    return m;
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!email.contains('@') || _password.text.length < 6) {
      setState(() => _message = 'Skriv inn e-post og et passord på minst 6 tegn.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_newUser) {
        final inn = await _cloud.signUp(email, _password.text);
        if (!inn) {
          setState(() {
            _busy = false;
            _newUser = false;
            _message = 'Kontoen er laget. Åpne e-posten fra Supabase og trykk på lenken for å bekrefte. '
                'Siden som åpnes kan vise en feilmelding – det gjør ingenting. Kom så tilbake hit og logg inn.';
          });
          return;
        }
      } else {
        await _cloud.signIn(email, _password.text);
      }
      final msg = await _cloud.afterLogin(_askWhichData);
      if (mounted) setState(() => _message = msg);
    } catch (e) {
      if (mounted) setState(() => _message = _norsk(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<CloudChoice?> _askWhichData(DateTime remote, DateTime? local) => showDialog<CloudChoice>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Text('Hvilke data skal brukes?'),
          content: Text('Det finnes en plan både i skyen (lagret ${fmtTid(remote.toLocal())}) '
              'og på denne telefonen${local == null ? '' : ' (endret ${fmtTid(local)})'}. '
              'Den du ikke velger, blir erstattet.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, CloudChoice.brukTelefon), child: const Text('Denne telefonen')),
            TextButton(onPressed: () => Navigator.pop(c, CloudChoice.brukSky), child: const Text('Skyen')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final u = _cloud.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Lagring i skyen')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Text(
            'Med konto lagres planen, øktene og målingene dine også i skyen (Supabase, EU). '
            'Da kan du bytte telefon uten å miste noe. Appen virker som før uten nett, og laster opp når den kan.',
            style: TextStyle(color: muted, fontSize: 14, height: 1.45),
          ),
          const SizedBox(height: 16),
          if (u != null) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_done),
                title: Text(u.email ?? 'Innlogget'),
                subtitle: Text(_cloud.syncing
                    ? 'Lagrer …'
                    : _cloud.lastUpload == null
                        ? 'Lagres automatisk ved endringer'
                        : 'Sist lagret ${fmtTid(_cloud.lastUpload!)}'),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _cloud.syncing || app.profile == null ? null : _cloud.upload,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Lagre nå'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        final r = await _cloud.fetchRemote();
                        if (r == null) {
                          _message = 'Det ligger ingen data i skyen ennå.';
                        } else if (context.mounted) {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Hente fra skyen?'),
                              content: Text('Dataene på telefonen erstattes med det som ble lagret ${fmtTid(r.updatedAt.toLocal())}.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Avbryt')),
                                TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Hent')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await app.replaceWith(r.data);
                            _message = 'Hentet fra skyen.';
                          }
                        }
                      } catch (e) {
                        _message = _norsk(e);
                      }
                      if (mounted) setState(() => _busy = false);
                    },
              icon: const Icon(Icons.cloud_download),
              label: const Text('Hent fra skyen'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _cloud.signOut, child: const Text('Logg ut')),
            const Text('Når du logger ut, blir dataene liggende både på telefonen og i skyen.',
                textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 13)),
          ] else ...[
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Logg inn')),
                ButtonSegment(value: true, label: Text('Ny konto')),
              ],
              selected: {_newUser},
              onSelectionChanged: (s) => setState(() => _newUser = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'E-post'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              autofillHints: [_newUser ? AutofillHints.newPassword : AutofillHints.password],
              decoration: InputDecoration(labelText: _newUser ? 'Velg passord (minst 6 tegn)' : 'Passord'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_newUser ? 'Lag konto' : 'Logg inn'),
            ),
            if (!_newUser)
              TextButton(
                onPressed: () async {
                  if (!_email.text.contains('@')) {
                    setState(() => _message = 'Skriv inn e-posten din først.');
                    return;
                  }
                  try {
                    await _cloud.resetPassword(_email.text);
                    setState(() => _message = 'Du har fått en e-post med lenke for å velge nytt passord.');
                  } catch (e) {
                    setState(() => _message = _norsk(e));
                  }
                },
                child: const Text('Glemt passord?'),
              ),
          ],
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4)),
          ],
          if (_cloud.lastError != null) ...[
            const SizedBox(height: 12),
            Text(_cloud.lastError!, style: const TextStyle(color: warnFg, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}
