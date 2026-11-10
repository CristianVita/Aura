import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum DownloadNetworkMode { wifiOnly, anyNetwork }

class DownloadNetworkException implements Exception {
  const DownloadNetworkException();
}

abstract class DownloadNetworkGuard {
  Future<bool> allowed();
  Stream<bool> get changes;
}

class DownloadNetworkPolicy extends ChangeNotifier
    implements DownloadNetworkGuard {
  DownloadNetworkPolicy({
    Connectivity? connectivity,
    Future<Directory> Function()? directory,
  }) : _connectivity = connectivity ?? Connectivity(),
       _directory = directory ?? getApplicationSupportDirectory;
  final Connectivity _connectivity;
  final Future<Directory> Function() _directory;
  DownloadNetworkMode mode = DownloadNetworkMode.wifiOnly;
  Future<void>? _loading;
  final _changes = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _ready = false;

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final file = File(
        p.join((await _directory()).path, 'download_network_policy.json'),
      );
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        mode = data is Map && data['mode'] == 'anyNetwork'
            ? DownloadNetworkMode.anyNetwork
            : DownloadNetworkMode.wifiOnly;
      }
    } catch (_) {
      mode = DownloadNetworkMode.wifiOnly;
    }
    _ready = true;
    notifyListeners();
  }

  bool get ready => _ready;

  Future<void> setMode(DownloadNetworkMode value) async {
    await load();
    final dir = await _directory();
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'download_network_policy.json'));
    await file.writeAsString(
      jsonEncode({'version': 1, 'mode': value.name}),
      flush: true,
    );
    mode = value;
    notifyListeners();
    _changes.add(await allowed());
  }

  @override
  Future<bool> allowed() async {
    await load();
    if (mode == DownloadNetworkMode.anyNetwork) return true;
    try {
      final state = await _connectivity.checkConnectivity();
      return _permits(state);
    } catch (_) {
      return false;
    }
  }

  bool _permits(List<ConnectivityResult> state) =>
      mode == DownloadNetworkMode.anyNetwork ||
      (state.isNotEmpty &&
          state.every((item) => item == ConnectivityResult.wifi));
  @override
  Stream<bool> get changes {
    _subscription ??= _connectivity.onConnectivityChanged.listen(
      (state) => _changes.add(_permits(state)),
      onError: (Object error, StackTrace stack) => _changes.add(false),
    );
    return _changes.stream;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _changes.close();
    super.dispose();
  }
}
