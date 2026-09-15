import 'package:flutter/material.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../persistence/session_store.dart';

/// Nextcloud / WebDAV settings + manual sync.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  String? _lastSync;
  String? _status;

  @override
  void initState() {
    super.initState();
    unawaitedLoad();
  }

  Future<void> unawaitedLoad() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _url.text = prefs.getString('sync_url') ?? '';
      _user.text = prefs.getString('sync_user') ?? '';
      _password.text = prefs.getString('sync_password') ?? '';
      _lastSync = prefs.getString('sync_last');
      _loading = false;
    });
  }

  Future<void> _saveCreds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync_url', _url.text.trim());
    await prefs.setString('sync_user', _user.text.trim());
    await prefs.setString('sync_password', _password.text);
  }

  WebDAVClient _client() {
    final url = _url.text.trim();
    if (url.isEmpty) {
      throw WebDavException('Enter a WebDAV URL (Nextcloud remote.php/dav/files/…)');
    }
    return WebDAVClient(
      baseUrl: url,
      username: _user.text.trim().isEmpty ? null : _user.text.trim(),
      password: _password.text,
    );
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await _saveCreds();
      await _client().connect();
      if (mounted) setState(() => _status = 'Connected');
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await _saveCreds();
      if (!mounted) return;
      final store = SessionStoreScope.of(context);
      final sync = ProgressorSync(_client(), storage: TestStorage());
      final result = await sync.sync();
      await store.load();
      final stamp = DateTime.now().toIso8601String();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sync_last', stamp);
      if (mounted) {
        setState(() {
          _lastSync = stamp;
          _status =
              'Pushed ${result.pushed} · pulled ${result.pulled} · skipped ${result.skipped}';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nextcloud Sync')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Sync tests across phone and desktop via WebDAV '
                  '(Nextcloud Files). Tests are stored as JSON under '
                  'progressor/tests/.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'WebDAV URL',
                    hintText:
                        'https://cloud.example/remote.php/dav/files/you/',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _user,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password / app password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (_lastSync != null)
                  Text(
                    'Last sync: $_lastSync',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                if (_status != null) ...[
                  const SizedBox(height: 8),
                  Text(_status!, key: const Key('sync_status')),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _test,
                        child: const Text('Test'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _sync,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync),
                        label: const Text('Sync now'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
