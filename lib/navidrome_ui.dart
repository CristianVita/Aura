import 'app_theme.dart';

import 'package:flutter/material.dart';

import 'navidrome.dart';

class NavidromeSourcesScreen extends StatefulWidget {
  const NavidromeSourcesScreen({super.key, required this.repository});
  final NavidromeRepository repository;
  @override
  State<NavidromeSourcesScreen> createState() => _NavidromeSourcesScreenState();
}

class _NavidromeSourcesScreenState extends State<NavidromeSourcesScreen> {
  List<NavidromeServer>? _servers;
  bool _busy = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final servers = await widget.repository.servers();
      if (mounted) setState(() => _servers = servers);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Nu am putut încărca sursele salvate. Încearcă din nou.',
        );
      }
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      await _load();
      if (mounted) setState(() => _message = success);
    } on NavidromeException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Nu am putut salva modificarea sursei. Încearcă din nou.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add([NavidromeServer? existing]) async {
    final server = await showDialog<NavidromeServer>(
      context: context,
      builder: (_) => _ConnectionDialog(existing: existing),
    );
    if (server == null || !mounted) return;
    await _run(
      () => widget.repository.connect(server),
      'Conectat. Biblioteca serverului a fost încărcată.',
    );
  }

  Future<void> _remove(NavidromeServer server) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deconectezi sursa?'),
        content: Text(
          '„${server.name}” va fi eliminată din Aura. Fișierele de pe server rămân intacte.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anulează'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Deconectează'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _run(
        () => widget.repository.remove(server.id),
        'Sursă deconectată.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Surse Navidrome'),
        automaticallyImplyLeading: !_busy,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Conectează biblioteca ta de pe un server Navidrome prin HTTPS.',
          ),
          const SizedBox(height: 12),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_message!),
            ),
          if (_busy)
            const Column(
              children: [
                LinearProgressIndicator(),
                SizedBox(height: 12),
                Text('Se încarcă biblioteca serverului…'),
              ],
            ),
          if (_servers == null && !_busy)
            TextButton(
              onPressed: _load,
              child: const Text('Reîncarcă sursele'),
            ),
          for (final server in _servers ?? <NavidromeServer>[])
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(server.base.toString()),
                    Wrap(
                      children: [
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(
                                  () => widget.repository.connect(server),
                                  'Bibliotecă actualizată.',
                                ),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Actualizează'),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => _add(server),
                          child: const Text('Reconectează'),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => _remove(server),
                          child: const Text('Deconectează'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _add,
            icon: const Icon(Icons.add),
            label: const Text('Adaugă server Navidrome'),
          ),
          const SizedBox(height: 20),
          Text(
            'Piesele apar în Colecție după conectare. Redarea necesită internet. Favoritele, ratingurile și playlisturile Aura rămân locale; nu modificăm biblioteca serverului.',
            style: TextStyle(color: context.auraMuted),
          ),
        ],
      ),
    ),
  );
}

class _ConnectionDialog extends StatefulWidget {
  const _ConnectionDialog({this.existing});
  final NavidromeServer? existing;
  @override
  State<_ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<_ConnectionDialog> {
  late final _name = TextEditingController(
    text: widget.existing?.name ?? 'Navidrome',
  );
  late final _url = TextEditingController(
    text: widget.existing?.base.toString(),
  );
  late final _user = TextEditingController(text: widget.existing?.username);
  final _password = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final server = NavidromeServer(
        url: _url.text,
        username: _user.text.trim(),
        password: _password.text,
        name: _name.text.trim(),
      );
      Navigator.pop(context, server);
    } on NavidromeException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Conectare Navidrome'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Numele sursei'),
            ),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'URL server',
                hintText: 'https://muzica.exemplu.ro',
              ),
            ),
            TextField(
              controller: _user,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Utilizator'),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Parolă'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            Text(
              'Datele de conectare sunt salvate în stocarea securizată a dispozitivului.',
              style: TextStyle(fontSize: 12, color: context.auraMuted),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Anulează'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Conectează')),
    ],
  );
}
