import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class MusicPlaylist {
  MusicPlaylist({
    required this.id,
    required this.name,
    Iterable<String> tracks = const [],
  }) : tracks = List.unmodifiable(tracks.toSet());
  final String id;
  final String name;
  final List<String> tracks;
  MusicPlaylist copy({String? name, Iterable<String>? tracks}) => MusicPlaylist(
    id: id,
    name: name ?? this.name,
    tracks: tracks ?? this.tracks,
  );
  Map<String, Object> toJson() => {'id': id, 'name': name, 'tracks': tracks};
}

class SavedMusicData {
  SavedMusicData({
    Iterable<String> favorites = const [],
    Iterable<MusicPlaylist> playlists = const [],
  }) : favorites = Set.unmodifiable(favorites),
       playlists = List.unmodifiable(playlists);
  final Set<String> favorites;
  final List<MusicPlaylist> playlists;
  String encode() => jsonEncode({
    'version': 1,
    'favorites': favorites.toList(),
    'playlists': playlists.map((p) => p.toJson()).toList(),
  });
  factory SavedMusicData.decode(String value) {
    final root = jsonDecode(value) as Map<String, dynamic>;
    if (root['version'] != 1) {
      throw const FormatException('Unsupported saved music version');
    }
    final favorites = (root['favorites'] as List).cast<String>();
    final playlists = (root['playlists'] as List).map((row) {
      final p = row as Map<String, dynamic>;
      final name = p['name'] as String;
      final id = p['id'] as String;
      if (name.trim().isEmpty || id.isEmpty) {
        throw const FormatException('Invalid playlist');
      }
      return MusicPlaylist(
        id: id,
        name: name,
        tracks: (p['tracks'] as List).cast<String>(),
      );
    }).toList();
    if (playlists.map((p) => p.id).toSet().length != playlists.length) {
      throw const FormatException('Duplicate playlist IDs');
    }
    return SavedMusicData(favorites: favorites, playlists: playlists);
  }
}

abstract class SavedMusicStorage {
  Future<String?> read();
  Future<void> write(String json);
}

class DeviceSavedMusicStorage implements SavedMusicStorage {
  static const _channel = MethodChannel(
    'com.example.symphonium_clone/audio_library',
  );
  @override
  Future<String?> read() => _channel.invokeMethod<String>('loadSavedMusic');
  @override
  Future<void> write(String json) =>
      _channel.invokeMethod<void>('saveSavedMusic', {'json': json});
}

class SavedMusicStore extends ChangeNotifier {
  SavedMusicStore(this.storage);
  final SavedMusicStorage storage;
  SavedMusicData _data = SavedMusicData();
  SavedMusicData get data => _data;
  bool ready = false;
  bool loadFailed = false;
  bool _disposed = false;
  int _counter = 0;
  Future<void> _pending = Future.value();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    ready = false;
    loadFailed = false;
    _notify();
    try {
      final saved = await storage.read();
      _data = saved == null ? SavedMusicData() : SavedMusicData.decode(saved);
      ready = true;
    } catch (_) {
      loadFailed = true;
    }
    _notify();
  }

  Future<void> _update(SavedMusicData Function(SavedMusicData) change) {
    final operation = _pending.then((_) async {
      if (!ready) throw StateError('Saved music unavailable');
      final next = change(_data);
      // Publish only after durable storage succeeds. A failed write cannot
      // erase previous state or poison the next queued edit.
      await storage.write(next.encode());
      _data = next;
      _notify();
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> toggleFavorite(String uri) => _update((data) {
    final favorites = {...data.favorites};
    if (!favorites.remove(uri)) favorites.add(uri);
    return SavedMusicData(favorites: favorites, playlists: data.playlists);
  });

  String _validName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      throw ArgumentError('Invalid name');
    }
    return trimmed;
  }

  Future<String> createPlaylist(
    String name, {
    Iterable<String> tracks = const [],
  }) async {
    final clean = _validName(name);
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
    await _update(
      (data) => SavedMusicData(
        favorites: data.favorites,
        playlists: [
          ...data.playlists,
          MusicPlaylist(id: id, name: clean, tracks: tracks),
        ],
      ),
    );
    return id;
  }

  Future<void> _editPlaylist(
    String id,
    MusicPlaylist Function(MusicPlaylist) edit,
  ) => _update((data) {
    if (!data.playlists.any((p) => p.id == id)) {
      throw StateError('Playlist removed');
    }
    return SavedMusicData(
      favorites: data.favorites,
      playlists: data.playlists.map((p) => p.id == id ? edit(p) : p),
    );
  });
  Future<void> renamePlaylist(String id, String name) =>
      _editPlaylist(id, (p) => p.copy(name: _validName(name)));
  Future<void> addTrack(String id, String uri) =>
      _editPlaylist(id, (p) => p.copy(tracks: [...p.tracks, uri]));
  Future<void> removeTrack(String id, String uri) =>
      _editPlaylist(id, (p) => p.copy(tracks: p.tracks.where((t) => t != uri)));
  Future<void> setTracks(String id, Iterable<String> uris) =>
      _editPlaylist(id, (p) => p.copy(tracks: uris));
  Future<void> deletePlaylist(String id) => _update(
    (data) => SavedMusicData(
      favorites: data.favorites,
      playlists: data.playlists.where((p) => p.id != id),
    ),
  );

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class SavedMusicScope extends InheritedNotifier<SavedMusicStore> {
  const SavedMusicScope({
    super.key,
    required SavedMusicStore store,
    required super.child,
  }) : super(notifier: store);
  static SavedMusicStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SavedMusicScope>()!.notifier!;
}
