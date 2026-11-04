import 'audio_library.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_runtime.dart';
import 'aura_backup.dart';
import 'backup_screen.dart';
import 'audio_features.dart';

import 'audio_track.dart';
import 'audio_sources.dart';
import 'navidrome_ui.dart';
import 'day_greeting.dart';
import 'playback_memory.dart';
import 'playback_memory_controller.dart';
import 'playback_memory_ui.dart';
import 'saved_music.dart';
import 'saved_music_ui.dart';
import 'playback_queue.dart';
import 'playback_settings_controller.dart';
import 'sleep_timer.dart';
import 'source_folders.dart';
import 'track_artwork.dart';

part 'search_screen.dart';
part 'settings_screen.dart';
part 'playback_settings_ui.dart';
part 'audio_features_ui.dart';

const _background = Color(0xFF0B1014);
const _surface = Color(0xFF141D22);
const _mint = Color(0xFF8BE0C0);
const _muted = Color(0xFFA4B3B8);
const _audioLibraryChannel = AudioLibrary();

enum _LibraryMode { songs, albums, artists, playlists, favorites }

extension on _LibraryMode {
  String get label => switch (this) {
    _LibraryMode.songs => 'Piese',
    _LibraryMode.albums => 'Albume',
    _LibraryMode.artists => 'Artiști',
    _LibraryMode.playlists => 'Playlisturi',
    _LibraryMode.favorites => 'Favorite',
  };

  IconData get icon => switch (this) {
    _LibraryMode.songs => Icons.music_note_rounded,
    _LibraryMode.albums => Icons.album_rounded,
    _LibraryMode.artists => Icons.person_rounded,
    _LibraryMode.playlists => Icons.queue_music_rounded,
    _LibraryMode.favorites => Icons.favorite_rounded,
  };
}

typedef _TrackSelection = Future<void> Function(
  List<AudioTrack> queue,
  int index,
);

late final AuraAudioRuntime _audioRuntime;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (AudioLibrary.isWindows ||
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)) {
      await BackupRestoreService.recover(
        journal: DeviceBackupJournal(),
        saved: DeviceSavedMusicStorage(),
        memory: DevicePlaybackMemoryStorage(),
      );
    }
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Aura nu a putut recupera o restaurare întreruptă. Datele anterioare sunt păstrate în jurnalul local. Închide și redeschide aplicația pentru a încerca din nou.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  final store = SavedMusicStore(DeviceSavedMusicStorage());
  await store.load();
  _audioRuntime = AuraAudioRuntime(store);
  await _audioRuntime.initializeService();
  runApp(const SoundLibraryApp());
}

class SoundLibraryApp extends StatefulWidget {
  const SoundLibraryApp({super.key});
  @override
  State<SoundLibraryApp> createState() => _SoundLibraryAppState();
}

class _SoundLibraryAppState extends State<SoundLibraryApp> {
  final _savedMusic = _audioRuntime.store;
  @override
  void dispose() {
    _savedMusic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SavedMusicScope(
      store: _savedMusic,
      child: MaterialApp(
        title: 'Aura',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _background,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _mint,
            brightness: Brightness.dark,
          ).copyWith(surface: _surface),
        ),
        home: const PlayerShell(),
      ),
    );
  }
}

class PlayerShell extends StatefulWidget {
  const PlayerShell({super.key});

  @override
  State<PlayerShell> createState() => _PlayerShellState();
}

class _PlayerShellState extends State<PlayerShell> {
  final AudioPlayer _player = _audioRuntime.player;
  PlaybackSettingsController? _playbackSettings;
  final _memory = PlaybackMemoryStore(DevicePlaybackMemoryStorage());
  late final PlaybackMemoryController _memoryController;
  late final StreamSubscription<SequenceState> _sequenceSubscription;
  int _selectedTab = 0;
  bool _isScanning = false;
  bool _isLoadingLibrary = true;
  List<AudioTrack> _allTracks = const [];
  Set<String>? _selectedFolders;
  bool _isManagingSources = false;
  List<AudioTrack> get _folderTracks => _selectedFolders == null
      ? _allTracks
      : _allTracks
            .where(
              (track) =>
                  track.uri.startsWith('aura://navidrome/') ||
                  _selectedFolders!.contains(track.folder),
            )
            .toList(growable: false);
  List<AudioTrack> get _tracks => _folderTracks
      .where(_memory.data.filters.includes)
      .toList(growable: false);
  List<AudioTrack> get _recentTracks {
    final byUri = {for (final track in _tracks) track.uri: track};
    return _memory.data.history
        .map((e) => byUri[e.uri])
        .whereType<AudioTrack>()
        .toList();
  }

  _LibraryMode _libraryMode = _LibraryMode.songs;
  bool _libraryOverview = true;
  final _searchQueries = <String>[];
  String? _groupFilter;

  @override
  void initState() {
    super.initState();
    _memory.addListener(_memoryChanged);
    _memoryController = PlaybackMemoryController(
      player: _player,
      store: _memory,
      onError: () {
        if (mounted) {
          _showMessage(
            'Nu am putut încărca sau salva istoricul și ultima redare.',
          );
        }
      },
    );
    _sequenceSubscription = _player.sequenceStateStream.listen((state) {
      if (!mounted) return;
      setState(() {});
    });
    _loadLibrary();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playbackSettings ??= PlaybackSettingsController(
      player: _player,
      store: SavedMusicScope.of(context),
      onError: () {
        if (mounted) {
          _showMessage(
            'Nu am putut aplica setările de redare sau temporizatorul.',
          );
        }
      },
    );
    _audioRuntime.allowCrossfade = () =>
        _playbackSettings?.sleep.waitingForTrack != true;
  }

  void _memoryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openBackup() async {
    final saved = SavedMusicScope.of(context);
    final service = BackupRestoreService(
      saved: saved,
      memory: _memory,
      journal: DeviceBackupJournal(),
      beforeRestore: () async {
        await _audioRuntime.pause();
        _playbackSettings?.sleep.cancel();
        await _memoryController.flush();
        _memoryController.beginQueueChange();
      },
      afterRestore: _memoryController.endQueueChange,
      applyPreferences: () async {
        await _playbackSettings?.applyStoredPreferences();
        await _audioRuntime.applyStoredAudioPreferences();
      },
    );
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => BackupScreen(
          saved: saved,
          memory: _memory,
          service: service,
          tracks: _allTracks,
        ),
      ),
    );
  }

  Future<void> _openFilters() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          LibraryFiltersScreen(store: _memory, tracks: _folderTracks),
    ),
  );

  Future<void> _openHistory() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => ListeningHistoryScreen(
        store: _memory,
        tracks: _tracks,
        onPlay: _playQueue,
      ),
    ),
  );

  Future<void> _loadLibrary({bool restorePlayback = true}) async {
    try {
      final rows = await _audioLibraryChannel.invokeListMethod<Object?>(
        'loadLibrary',
      );
      final selected = await _audioLibraryChannel.invokeListMethod<String>(
        'loadSourceFolders',
      );
      if (!mounted) return;
      setState(() {
        _selectedFolders = selected?.toSet();
        _allTracks = (rows ?? const <Object?>[])
            .whereType<Map<Object?, Object?>>()
            .map(AudioTrack.fromMap)
            .toList(growable: false);
      });
      if (restorePlayback) await _memoryController.initialize(_allTracks);
    } on MissingPluginException {
      // Other platforms will provide their own library storage adapter.
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Nu am putut încărca biblioteca. Scanează muzica din nou.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingLibrary = false);
    }
  }

  Future<void> _manageSourceFolders() async {
    if (_isScanning || _isLoadingLibrary || _isManagingSources) return;
    _isManagingSources = true;
    try {
      final type = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.folder_open_rounded),
                title: Text(
                  AudioLibrary.isWindows
                      ? 'Muzică de pe PC'
                      : 'Muzică de pe telefon',
                ),
                onTap: () => Navigator.pop(context, 'local'),
              ),
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Server Navidrome'),
                subtitle: const Text('URL și cont de utilizator'),
                onTap: () => Navigator.pop(context, 'server'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || type == null) return;
      if (type == 'server') {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                NavidromeSourcesScreen(repository: AudioLibrary.navidrome),
          ),
        );
        if (mounted) await _loadLibrary(restorePlayback: false);
      } else {
        await _manageSourceFoldersInner();
      }
    } catch (_) {
      if (mounted) _showMessage('Nu am putut încărca sursele muzicale.');
    } finally {
      _isManagingSources = false;
    }
  }

  Future<void> _manageSourceFoldersInner() async {
    if (AudioLibrary.isWindows) {
      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Adaugă un folder de pe PC'),
                onTap: () => Navigator.pop(context, 'add'),
              ),
              ListTile(
                leading: const Icon(Icons.checklist_rounded),
                title: const Text('Alege folderele vizibile'),
                onTap: () => Navigator.pop(context, 'visible'),
              ),
              ListTile(
                leading: const Icon(Icons.folder_off_outlined),
                title: const Text('Elimină un folder din bibliotecă'),
                subtitle: const Text('Fișierele rămân pe PC.'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
            ],
          ),
        ),
      );
      if (action == null || !mounted) return;
      if (action == 'remove') {
        final roots =
            await _audioLibraryChannel.invokeListMethod<String>(
              'loadAudioRoots',
            ) ??
            [];
        if (!mounted) return;
        if (roots.isEmpty) {
          _showMessage('Nu ai adăugat încă niciun folder.');
          return;
        }
        final folder = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Elimină din bibliotecă'),
            children: roots
                .map(
                  (root) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, root),
                    child: Text(root),
                  ),
                )
                .toList(),
          ),
        );
        if (folder == null || !mounted) return;
        setState(() => _isScanning = true);
        try {
          final rows = await _audioLibraryChannel.invokeListMethod<Object?>(
            'removeAudioFolder',
            {'folder': folder},
          );
          if (!mounted) return;
          setState(
            () => _allTracks = (rows ?? [])
                .whereType<Map<Object?, Object?>>()
                .map(AudioTrack.fromMap)
                .toList(),
          );
          _showMessage(
            'Folder eliminat din bibliotecă. Fișierele au rămas pe PC.',
          );
        } catch (_) {
          if (mounted) {
            _showMessage('Nu am putut elimina folderul din bibliotecă.');
          }
        } finally {
          if (mounted) setState(() => _isScanning = false);
        }
        return;
      }
      if (action == 'add') {
        setState(() => _isScanning = true);
        try {
          final rows = await _audioLibraryChannel.invokeListMethod<Object?>(
            'chooseAudioFolder',
          );
          final selected = await _audioLibraryChannel.invokeListMethod<String>(
            'loadSourceFolders',
          );
          if (rows == null || !mounted) return;
          setState(() {
            _allTracks = rows
                .whereType<Map<Object?, Object?>>()
                .map(AudioTrack.fromMap)
                .toList();
            _selectedFolders = selected?.toSet();
            _selectedTab = 1;
            _libraryMode = _LibraryMode.songs;
            _groupFilter = null;
          });
          _showMessage('${_tracks.length} piese în bibliotecă.');
        } catch (_) {
          if (mounted) {
            _showMessage(
              'Nu am putut citi folderul. Verifică dacă este disponibil.',
            );
          }
        } finally {
          if (mounted) setState(() => _isScanning = false);
        }
        return;
      }
    }
    _isManagingSources = true;
    try {
      if (_allTracks.isEmpty) await _scanAudio();
      if (!mounted || _allTracks.isEmpty) return;
      final counts = <String, int>{};
      for (final track in _allTracks.where(
        (track) => !track.uri.startsWith('aura://navidrome/'),
      )) {
        counts.update(track.folder, (value) => value + 1, ifAbsent: () => 1);
      }
      for (final folder in _selectedFolders ?? <String>{}) {
        counts.putIfAbsent(folder, () => 0);
      }
      final selection = await Navigator.of(context).push<SourceFolderSelection>(
        MaterialPageRoute(
          builder: (_) => SourceFoldersScreen(
            folderCounts: counts,
            selectedFolders: _selectedFolders,
          ),
        ),
      );
      if (selection == null || !mounted) return;
      await _audioLibraryChannel.invokeMethod<void>('saveSourceFolders', {
        'folders': selection.folders?.toList(),
      });
      if (!mounted) return;
      setState(() => _selectedFolders = selection.folders);
      _showMessage(
        'Surse salvate. ${_tracks.length} ${_tracks.length == 1 ? 'piesă' : 'piese'} în bibliotecă.',
      );
    } catch (_) {
      if (mounted) _showMessage('Nu am putut salva sursele. Încearcă din nou.');
    } finally {
      _isManagingSources = false;
    }
  }

  AudioTrack? get _currentTrack =>
      audioTrackOf(_player.sequenceState.currentSource);

  Future<void> _playQueue(List<AudioTrack> queue, int index) async {
    if (queue.isEmpty || index < 0 || index >= queue.length) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _memoryController.beginQueueChange();
    try {
      await _player.pause();
      await _player.setAudioSources(
        await Future.wait(queue.map(sourceForTrack)),
        initialIndex: index,
        initialPosition: Duration.zero,
      );
      _memoryController.endQueueChange();
      await _memoryController.flush();
      await _audioRuntime.play();
    } catch (_) {
      _memoryController.endQueueChange();
      if (!mounted) return;
      _showMessage('Nu am putut reda piesa. Încearcă să o scanezi din nou.');
    }
  }

  Future<void> _openNowPlaying() async {
    if (_currentTrack == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (context) =>
          _NowPlayingSheet(player: _player, controls: _playbackSettings!),
    );
  }

  @override
  void dispose() {
    _playbackSettings?.dispose();
    _memoryController.dispose();
    _memory.removeListener(_memoryChanged);
    _memory.dispose();
    _sequenceSubscription.cancel();
    unawaited(_audioRuntime.dispose());
    super.dispose();
  }

  void _openLibrary(_LibraryMode mode) {
    setState(() {
      _selectedTab = 1;
      _libraryMode = mode;
      _libraryOverview = false;
      _groupFilter = null;
    });
  }

  void _selectTab(int index) => setState(() {
    _selectedTab = index;
    if (index == 1) _libraryOverview = true;
  });

  void _openSearch() => setState(() => _selectedTab = 2);

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _scanAudio() async {
    if (_isScanning || _isLoadingLibrary) return;
    setState(() => _isScanning = true);

    try {
      final hasServerTracks = _allTracks.any(
        (track) => track.uri.startsWith('aura://navidrome/'),
      );
      if (hasServerTracks) {
        for (final server in await AudioLibrary.navidrome.servers()) {
          await AudioLibrary.navidrome.connect(server);
        }
      }
      final serverOnly =
          hasServerTracks &&
          _allTracks.every(
            (track) => track.uri.startsWith('aura://navidrome/'),
          );
      final rows =
          await _audioLibraryChannel.invokeListMethod<Object?>(
            serverOnly ? 'loadLibrary' : 'scanAudio',
          ) ??
          const <Object?>[];
      final tracks = rows
          .whereType<Map<Object?, Object?>>()
          .map(AudioTrack.fromMap)
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _allTracks = tracks;
        _selectedTab = 1;
      });
      _showMessage(
        _tracks.isEmpty
            ? 'Nu am găsit fișiere muzicale pe dispozitiv.'
            : '${_tracks.length} ${_tracks.length == 1 ? 'piesă' : 'piese'} în folderele selectate.',
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      _showMessage(
        error.code == 'permission_denied'
            ? 'Permite accesul la muzică pentru a scana biblioteca.'
            : 'Nu am putut scana muzica. Încearcă din nou.',
      );
    } on MissingPluginException {
      if (!mounted) return;
      _showMessage(
        'Scanarea bibliotecii este disponibilă momentan pe Android.',
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage('A apărut o problemă la scanarea muzicii.');
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Widget _page() {
    switch (_selectedTab) {
      case 0:
        return _HomeScreen(
          onAddSource: _manageSourceFolders,
          onSearch: _openSearch,
          onBrowse: _openLibrary,
          trackCount: _tracks.length,
          tracks: _tracks,
          recentTracks: _recentTracks,
          onPlay: _playQueue,
          onHistory: _openHistory,
          isScanning: _isScanning,
        );
      case 1:
        if (_libraryOverview) {
          return _LibraryOverview(
            trackCount: _tracks.length,
            onBrowse: _openLibrary,
            onSources: _manageSourceFolders,
          );
        }
        if (_libraryMode == _LibraryMode.playlists ||
            _libraryMode == _LibraryMode.favorites) {
          return SavedMusicScreen(
            key: ValueKey(_libraryMode),
            tracks: _tracks,
            onPlay: _playQueue,
            initialFavorites: _libraryMode == _LibraryMode.favorites,
          );
        }
        return _CollectionScreen(
          tracks: _tracks,
          hasHiddenTracks: _folderTracks.isNotEmpty,
          onFilters: _openFilters,
          isScanning: _isScanning,
          onAddSource: _scanAudio,
          onManageSources: _manageSourceFolders,
          mode: _libraryMode,
          groupFilter: _groupFilter,
          onOpenGroup: (group) => setState(() => _groupFilter = group),
          onBackToGroups: () => setState(() => _groupFilter = null),
          onTrackSelected: _playQueue,
        );
      case 2:
        return SearchScreen(
          tracks: _tracks,
          recentQueries: _searchQueries,
          isScanning: _isScanning,
          onAddSource: _manageSourceFolders,
          onTrackSelected: _playQueue,
        );
      default:
        return SettingsScreen(
          onBackup: _openBackup,
          controls: _playbackSettings!,
          sourceSummary: _selectedFolders == null
              ? 'Toate folderele · ${_tracks.length} piese'
              : '${_selectedFolders!.length} ${_selectedFolders!.length == 1 ? 'folder selectat' : 'foldere selectate'} · ${_tracks.length} ${_tracks.length == 1 ? 'piesă' : 'piese'}',
          onManageSources: _manageSourceFolders,
          onFilters: _openFilters,
          filtersReady: _memory.ready,
          onHistory: _openHistory,
          onScan: _scanAudio,
          isScanning: _isScanning,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AudioLibrary.isWindows && MediaQuery.sizeOf(context).width >= 900) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                extended: true,
                backgroundColor: _surface,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Aura',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: _mint,
                    ),
                  ),
                ),
                selectedIndex: _selectedTab,
                onDestinationSelected: _selectTab,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.home_outlined),
                    label: Text('Acasă'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.library_music_outlined),
                    label: Text('Colecție'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.search_rounded),
                    label: Text('Caută'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.tune_rounded),
                    label: Text('Setări'),
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1100),
                          child: _isLoadingLibrary
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: _mint,
                                  ),
                                )
                              : _page(),
                        ),
                      ),
                    ),
                    if (_currentTrack != null)
                      _MiniPlayer(
                        track: _currentTrack!,
                        player: _player,
                        onTap: _openNowPlaying,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: _isLoadingLibrary
            ? const Center(child: CircularProgressIndicator(color: _mint))
            : _page(),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_currentTrack != null)
            _MiniPlayer(
              track: _currentTrack!,
              player: _player,
              onTap: _openNowPlaying,
            ),
          NavigationBar(
            height: 56,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
            backgroundColor: _surface,
            indicatorColor: _mint.withValues(alpha: 0.16),
            selectedIndex: _selectedTab,
            onDestinationSelected: _selectTab,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Acasă',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music_rounded),
                label: 'Colecție',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_rounded),
                label: 'Caută',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_rounded),
                label: 'Setări',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen({
    required this.onAddSource,
    required this.onSearch,
    required this.onBrowse,
    required this.trackCount,
    required this.tracks,
    required this.recentTracks,
    required this.onPlay,
    required this.onHistory,
    required this.isScanning,
  });

  final VoidCallback onAddSource;
  final VoidCallback onSearch;
  final ValueChanged<_LibraryMode> onBrowse;
  final int trackCount;
  final List<AudioTrack> tracks;
  final List<AudioTrack> recentTracks;
  final _TrackSelection onPlay;
  final VoidCallback onHistory;
  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    final favorites = tracks
        .where(
          (track) =>
              SavedMusicScope.of(context).data.favorites.contains(track.uri),
        )
        .toList();
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          sliver: SliverList.list(
            children: [
              _TopBar(onSearch: onSearch),
              const SizedBox(height: 28),
              DayGreeting(
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                trackCount == 0
                    ? 'Unde se află muzica ta?'
                    : '$trackCount de piese, în ritmul tău.',
                style: const TextStyle(color: _muted, fontSize: 14),
              ),
              const SizedBox(height: 22),
              if (trackCount == 0)
                _SourceCard(onTap: onAddSource, isScanning: isScanning)
              else
                _HomeShortcuts(onBrowse: onBrowse),
              if (favorites.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Expanded(
                      child: _SectionTitle(title: 'Piese favorite'),
                    ),
                    IconButton(
                      tooltip: 'Toate favoritele',
                      onPressed: () => onBrowse(_LibraryMode.favorites),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                for (var i = 0; i < favorites.length && i < 3; i++)
                  _AudioTrackTile(
                    track: favorites[i],
                    onTap: () => onPlay(favorites, i),
                  ),
              ],
              if (trackCount == 0) ...[
                const SizedBox(height: 30),
                _SectionTitle(
                  title: 'Răsfoiește',
                  trailing:
                      '$trackCount ${trackCount == 1 ? 'piesă' : 'piese'}',
                ),
                const SizedBox(height: 14),
                _BrowseGrid(onTap: onBrowse),
              ],
              const SizedBox(height: 30),
              Row(
                children: [
                  const Expanded(
                    child: _SectionTitle(title: 'Ascultate recent'),
                  ),
                  TextButton(
                    onPressed: onHistory,
                    child: const Text('Vezi tot'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (recentTracks.isEmpty)
                const _EmptyListeningCard()
              else
                for (
                  var index = 0;
                  index < recentTracks.length && index < 5;
                  index++
                )
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _AudioTrackTile(
                      track: recentTracks[index],
                      onTap: () => onPlay(recentTracks, index),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _mint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset('assets/branding/aura.png'),
          ),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AURA',
              style: TextStyle(
                color: _muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.7,
              ),
            ),
            SizedBox(height: 3),
            Text(
              'Biblioteca ta',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const Spacer(),
        IconButton.filledTonal(
          tooltip: 'Caută',
          onPressed: onSearch,
          icon: const Icon(Icons.search_rounded),
          style: IconButton.styleFrom(
            backgroundColor: _surface,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.onTap, required this.isScanning});

  final VoidCallback onTap;
  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: isScanning ? null : onTap,
        borderRadius: BorderRadius.circular(26),
        child: Ink(
          height: 218,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF183A37), Color(0xFF14272D), Color(0xFF17202B)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -42,
                top: -74,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _mint.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Positioned(
                right: 15,
                bottom: 4,
                child: Icon(
                  Icons.graphic_eq_rounded,
                  size: 116,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(21),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'ÎNCEPE CU O SURSĂ',
                        style: TextStyle(
                          color: _mint,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'Adaugă muzica ta',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      AudioLibrary.isWindows
                          ? 'PC sau server Navidrome'
                          : 'Telefon sau server Navidrome',
                      style: TextStyle(color: Color(0xFFC2D1D0), fontSize: 14),
                    ),
                    const SizedBox(height: 15),
                    FilledButton.icon(
                      onPressed: isScanning ? null : onTap,
                      icon: isScanning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF10211D),
                              ),
                            )
                          : const Icon(Icons.add_rounded, size: 19),
                      label: Text(
                        isScanning ? 'Se scanează...' : 'Adaugă o sursă',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _mint,
                        foregroundColor: const Color(0xFF10211D),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        if (trailing != null)
          Text(trailing!, style: const TextStyle(color: _muted, fontSize: 12)),
      ],
    );
  }
}

class _BrowseGrid extends StatelessWidget {
  const _BrowseGrid({required this.onTap, this.onSources});
  final ValueChanged<_LibraryMode> onTap;
  final VoidCallback? onSources;
  @override
  Widget build(BuildContext context) {
    final items = [
      _LibraryMode.albums,
      _LibraryMode.artists,
      _LibraryMode.songs,
      _LibraryMode.playlists,
      _LibraryMode.favorites,
    ];
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length + (onSources == null ? 0 : 1),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: constraints.maxWidth >= 650 ? 6 : 3,
          mainAxisExtent: 112,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemBuilder: (context, index) {
          final item = index < items.length ? items[index] : null;
          return Material(
            color: _surface,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: item == null ? onSources : () => onTap(item),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item?.icon ?? Icons.folder_open_outlined,
                      color: _mint,
                      size: 26,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      item?.label ?? 'Surse',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LibraryOverview extends StatelessWidget {
  const _LibraryOverview({
    required this.trackCount,
    required this.onBrowse,
    required this.onSources,
  });
  final int trackCount;
  final ValueChanged<_LibraryMode> onBrowse;
  final VoidCallback onSources;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
    children: [
      const Row(
        children: [
          Icon(Icons.library_music_outlined, size: 22),
          SizedBox(width: 14),
          Text('Bibliotecă', style: TextStyle(fontSize: 23)),
        ],
      ),
      const SizedBox(height: 22),
      _BrowseGrid(onTap: onBrowse, onSources: onSources),
      const SizedBox(height: 18),
      Text(
        '$trackCount de piese în bibliotecă',
        style: const TextStyle(color: _muted),
      ),
    ],
  );
}

class _HomeShortcuts extends StatelessWidget {
  const _HomeShortcuts({required this.onBrowse});
  final ValueChanged<_LibraryMode> onBrowse;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final mode in [
        _LibraryMode.songs,
        _LibraryMode.albums,
        _LibraryMode.favorites,
      ])
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Material(
              color: _mint.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => onBrowse(mode),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  child: Column(
                    children: [
                      Icon(mode.icon, color: _mint),
                      const SizedBox(height: 9),
                      Text(mode.label, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _EmptyListeningCard extends StatelessWidget {
  const _EmptyListeningCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: const Row(
        children: [
          Icon(Icons.history_rounded, color: _muted, size: 24),
          SizedBox(width: 13),
          Expanded(
            child: Text(
              'Istoricul tău de ascultare va apărea aici.',
              style: TextStyle(color: _muted, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionScreen extends StatelessWidget {
  const _CollectionScreen({
    required this.tracks,
    required this.isScanning,
    required this.onAddSource,
    required this.onManageSources,
    required this.mode,
    required this.groupFilter,
    required this.onOpenGroup,
    required this.onBackToGroups,
    required this.onTrackSelected,
    required this.hasHiddenTracks,
    required this.onFilters,
  });

  final List<AudioTrack> tracks;
  final bool isScanning;
  final VoidCallback onAddSource;
  final VoidCallback onManageSources;
  final _LibraryMode mode;
  final bool hasHiddenTracks;
  final VoidCallback onFilters;
  final String? groupFilter;
  final ValueChanged<String> onOpenGroup;
  final VoidCallback onBackToGroups;
  final _TrackSelection onTrackSelected;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return _SimplePage(
        eyebrow: 'COLECȚIA TA',
        title: 'Biblioteca',
        message: hasHiddenTracks
            ? 'Nicio piesă nu corespunde filtrelor selectate.'
            : 'Alege folderele cu muzică pentru a vedea piesele în bibliotecă.',
        icon: Icons.library_music_outlined,
        actionLabel: hasHiddenTracks
            ? 'Modifică filtrele'
            : isScanning
            ? 'Se scanează...'
            : 'Alege folderele',
        onAction: hasHiddenTracks
            ? onFilters
            : isScanning
            ? null
            : onManageSources,
      );
    }

    final ratedTracks = SavedMusicScope.of(context).data.ratedTracks(tracks);
    final filteredTracks = groupFilter == null
        ? ratedTracks
        : ratedTracks
              .where((track) {
                final value = mode == _LibraryMode.artists
                    ? track.artist
                    : track.album;
                return value == groupFilter;
              })
              .toList(growable: false);
    final showGroups = mode != _LibraryMode.songs && groupFilter == null;
    final groups = <String, List<AudioTrack>>{};
    if (showGroups) {
      for (final track in ratedTracks) {
        final value = mode == _LibraryMode.artists ? track.artist : track.album;
        groups.putIfAbsent(value, () => []).add(track);
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 14, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'COLECȚIA TA',
                      style: TextStyle(
                        color: _mint,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      groupFilter == ''
                          ? 'Necunoscut'
                          : groupFilter ?? mode.label,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (groupFilter != null)
                IconButton.filledTonal(
                  tooltip: 'Înapoi la ${mode.label.toLowerCase()}',
                  onPressed: onBackToGroups,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              IconButton.filledTonal(
                tooltip: 'Scanează din nou',
                onPressed: isScanning ? null : onAddSource,
                icon: isScanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: 'Alege folderele',
                onPressed: isScanning ? null : onManageSources,
                icon: const Icon(Icons.folder_open_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              showGroups
                  ? '${groups.length} ${groups.length == 1 ? 'element' : 'elemente'}'
                  : '${filteredTracks.length} ${filteredTracks.length == 1 ? 'piesă găsită' : 'piese găsite'}',
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 22),
          child: RatingViewControls(),
        ),
        Expanded(
          child: filteredTracks.isEmpty
              ? const Center(
                  child: Text('Nicio piesă nu corespunde ratingului selectat.'),
                )
              : showGroups
              ? ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                  itemCount: groups.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 2),
                  itemBuilder: (context, index) {
                    final entry = groups.entries.elementAt(index);
                    return Card(
                      color: _surface,
                      margin: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        onTap: () => onOpenGroup(entry.key),
                        leading: TrackArtwork(
                          uri: entry.value.first.artworkUri.toString(),
                          cacheKey: entry.value.first.artworkKey,
                          size: 46,
                          fallbackIcon: mode.icon,
                        ),
                        title: Text(
                          entry.key.isEmpty ? 'Necunoscut' : entry.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${entry.value.length} ${entry.value.length == 1 ? 'piesă' : 'piese'}',
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: _muted,
                        ),
                      ),
                    );
                  },
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                  itemCount: filteredTracks.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 2),
                  itemBuilder: (context, index) => _AudioTrackTile(
                    track: filteredTracks[index],
                    onTap: () => onTrackSelected(filteredTracks, index),
                  ),
                ),
        ),
      ],
    );
  }
}

class _AudioTrackTile extends StatelessWidget {
  const _AudioTrackTile({required this.track, required this.onTap});

  final AudioTrack track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final seconds = track.durationMs ~/ 1000;
    final duration =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    final details = [
      if (track.artist.isNotEmpty) track.artist,
      if (track.album.isNotEmpty) track.album,
    ].join(' · ');

    return Card(
      color: _surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: onTap,
        onLongPress: () => _showTrackDetails(context, track),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        leading: TrackArtwork(
          uri: track.artworkUri.toString(),
          cacheKey: track.artworkKey,
          size: 46,
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                details.isEmpty ? 'Artist necunoscut' : details,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ),
            TrackRatingBadge(uri: track.uri),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(duration, style: const TextStyle(color: _muted, fontSize: 12)),
            SavedTrackActions(track: track),
          ],
        ),
      ),
    );
  }
}

Future<void> _togglePlayback(BuildContext context, AudioPlayer player) async {
  try {
    final duration = player.duration;
    final atEnd =
        player.processingState == ProcessingState.completed ||
        (duration != null &&
            duration > Duration.zero &&
            player.position >= duration);
    if (atEnd) {
      await player.seek(Duration.zero);
      await _audioRuntime.play();
    } else if (player.playing) {
      await _audioRuntime.pause();
    } else {
      await player.play();
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nu am putut relua piesa. Încearcă să o alegi din nou.',
          ),
        ),
      );
    }
  }
}

Future<void> _showTrackDetails(BuildContext context, AudioTrack track) {
  final seconds = track.durationMs ~/ 1000;
  final duration = seconds > 0
      ? '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
      : 'Durată necunoscută';
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _surface,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Informații piesă',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Închide',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              track.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Center(
              child: TrackRating(key: ValueKey(track.uri), uri: track.uri),
            ),
            for (final detail in [
              (
                'Artist',
                track.artist.isEmpty ? 'Artist necunoscut' : track.artist,
              ),
              ('Album', track.album.isEmpty ? 'Album necunoscut' : track.album),
              ('Durată', duration),
              (
                'Folder',
                track.folder.isEmpty ? 'Folder necunoscut' : track.folder,
              ),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.$1,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(detail.$2),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({
    required this.track,
    required this.player,
    required this.onTap,
  });

  final AudioTrack track;
  final AudioPlayer player;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Material(
        color: _mint.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 3, 4, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    TrackArtwork(
                      uri: track.artworkUri.toString(),
                      cacheKey: track.artworkKey,
                      size: 42,
                      radius: 6,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            track.artist.isEmpty
                                ? 'Artist necunoscut'
                                : track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    StreamBuilder<PlayerState>(
                      stream: player.playerStateStream,
                      builder: (context, snapshot) {
                        final isPlaying =
                            (snapshot.data?.playing ?? false) &&
                            snapshot.data?.processingState !=
                                ProcessingState.completed;
                        return IconButton(
                          tooltip: isPlaying ? 'Pauză' : 'Redă',
                          onPressed: () => _togglePlayback(context, player),
                          icon: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: _mint,
                            size: 30,
                          ),
                        );
                      },
                    ),
                    SavedTrackActions(track: track, showPlaylist: false),
                    IconButton(
                      tooltip: 'Piesa următoare',
                      onPressed: player.hasNext
                          ? () => _audioRuntime.skip(true)
                          : null,
                      icon: const Icon(Icons.skip_next_rounded, color: _muted),
                    ),
                  ],
                ),
                StreamBuilder<Duration>(
                  stream: player.positionStream,
                  builder: (context, positionSnapshot) {
                    final position = positionSnapshot.data ?? Duration.zero;
                    return StreamBuilder<Duration?>(
                      stream: player.durationStream,
                      builder: (context, durationSnapshot) {
                        final total =
                            durationSnapshot.data?.inMilliseconds ?? 0;
                        final value = total <= 0
                            ? 0.0
                            : (position.inMilliseconds / total).clamp(0.0, 1.0);
                        return LinearProgressIndicator(
                          value: value,
                          minHeight: 2,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          color: _mint,
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NowPlayingSheet extends StatelessWidget {
  const _NowPlayingSheet({required this.player, required this.controls});
  final PlaybackSettingsController controls;

  final AudioPlayer player;

  String _format(Duration duration) {
    final seconds = duration.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            14,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: StreamBuilder<SequenceState>(
            stream: player.sequenceStateStream,
            initialData: player.sequenceState,
            builder: (context, snapshot) {
              final track = audioTrackOf(snapshot.data?.currentSource);
              if (track == null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Coada este goală'),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: TrackArtwork(
                      uri: track.artworkUri.toString(),
                      cacheKey: track.artworkKey,
                      size: (MediaQuery.sizeOf(context).width - 48).clamp(
                        180.0,
                        380.0,
                      ),
                      radius: 12,
                      fallbackIcon: Icons.graphic_eq_rounded,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          track.title,
                          textAlign: TextAlign.start,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SavedTrackActions(track: track, showPlaylist: false),
                      IconButton(
                        tooltip: 'Informații piesă',
                        onPressed: () => _showTrackDetails(context, track),
                        icon: const Icon(
                          Icons.info_outline_rounded,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    track.artist.isEmpty ? 'Artist necunoscut' : track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 15),
                  ),
                  if (track.album.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      track.album,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const SizedBox(height: 10),
                  StreamBuilder<Duration>(
                    stream: player.positionStream,
                    builder: (context, positionSnapshot) {
                      final position = positionSnapshot.data ?? Duration.zero;
                      return StreamBuilder<Duration?>(
                        stream: player.durationStream,
                        builder: (context, durationSnapshot) {
                          final duration =
                              durationSnapshot.data ??
                              Duration(milliseconds: track.durationMs);
                          final max = duration.inMilliseconds > 0
                              ? duration.inMilliseconds.toDouble()
                              : 1.0;
                          final value = position.inMilliseconds
                              .toDouble()
                              .clamp(0.0, max);
                          return Column(
                            children: [
                              Slider(
                                value: value,
                                max: max,
                                onChanged: duration.inMilliseconds <= 0
                                    ? null
                                    : (next) => player.seek(
                                        Duration(milliseconds: next.round()),
                                      ),
                                activeColor: _mint,
                                inactiveColor: Colors.white12,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _format(position),
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      _format(duration),
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TrackRating(key: ValueKey(track.uri), uri: track.uri),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Piesa anterioară',
                        onPressed: player.hasPrevious
                            ? () => _audioRuntime.skip(false)
                            : null,
                        icon: const Icon(Icons.skip_previous_rounded, size: 36),
                      ),
                      const SizedBox(width: 20),
                      StreamBuilder<PlayerState>(
                        stream: player.playerStateStream,
                        builder: (context, snapshot) {
                          final isPlaying =
                              (snapshot.data?.playing ?? false) &&
                              snapshot.data?.processingState !=
                                  ProcessingState.completed;
                          return IconButton.filled(
                            tooltip: isPlaying ? 'Pauză' : 'Redă',
                            onPressed: () => _togglePlayback(context, player),
                            iconSize: 34,
                            style: IconButton.styleFrom(
                              backgroundColor: _mint,
                              foregroundColor: _background,
                              minimumSize: const Size(68, 68),
                            ),
                            icon: Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 20),
                      IconButton(
                        tooltip: 'Piesa următoare',
                        onPressed: player.hasNext
                            ? () => player.seekToNext()
                            : null,
                        icon: const Icon(Icons.skip_next_rounded, size: 36),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  PlaybackOptions(player: player),
                  _PlaybackQuickSettings(controls: controls),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SimplePage extends StatelessWidget {
  const _SimplePage({
    required this.eyebrow,
    required this.title,
    required this.message,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String eyebrow;
  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _mint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, color: _mint, size: 34),
            ),
            const SizedBox(height: 24),
            Text(
              eyebrow,
              style: const TextStyle(
                color: _mint,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.7,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, height: 1.5),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
