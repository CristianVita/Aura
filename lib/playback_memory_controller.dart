import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_track.dart';
import 'playback_memory.dart';

class PlaybackMemoryController with WidgetsBindingObserver {
  PlaybackMemoryController({
    required this.player,
    required this.store,
    required this.onError,
  });
  final AudioPlayer player;
  final PlaybackMemoryStore store;
  final VoidCallback onError;
  final _history = ListeningProgress();
  final _clock = Stopwatch()..start();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _tick;
  Timer? _saveTimer;
  bool _active = false;
  bool _disposed = false;
  bool _reportedError = false;
  bool _hearing = false;
  String? _heardUri;
  int _lastTick = 0;
  int _lastSave = 0;
  bool _completed = false;
  bool _replacingQueue = false;
  bool _hasLoadedQueue = false;
  int _heardDurationMs = 0;

  Future<void> initialize(List<AudioTrack> library) async {
    await store.load();
    if (_disposed || !store.ready) {
      if (!_disposed) onError();
      return;
    }
    final session = store.data.session?.resolve(library);
    if (session != null && session.tracks.isNotEmpty) {
      try {
        await player.pause();
        await player.setAudioSources(
          session.tracks
              .map(
                (track) => AudioSource.uri(
                  Uri.parse(track.uri),
                  tag: track.toMediaItem(),
                ),
              )
              .toList(),
          initialIndex: session.index,
          initialPosition: Duration(milliseconds: session.positionMs),
          shuffleOrder: RestoredShuffleOrder(session.order),
        );
        await player.setLoopMode(session.loop);
        await player.setShuffleModeEnabled(session.shuffle);
        _hasLoadedQueue = true;
      } catch (_) {
        if (!_disposed) onError();
      }
    }
    if (_disposed) return;
    _active = true;
    _lastTick = _clock.elapsedMilliseconds;
    WidgetsBinding.instance.addObserver(this);
    _subscriptions.add(
      player.sequenceStateStream.listen((_) {
        _observe();
        _scheduleSave();
      }),
    );
    _subscriptions.add(
      player.playerStateStream.listen((_) {
        _observe();
        _scheduleSave();
      }),
    );
    _subscriptions.add(
      player.positionDiscontinuityStream.listen((event) {
        _observe();
        if (event.reason == PositionDiscontinuityReason.autoAdvance) {
          _history.restart();
        }
        _scheduleSave();
      }),
    );
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _observe();
      final now = _clock.elapsedMilliseconds;
      if (_hearing && now - _lastSave >= 3000) unawaited(flush());
    });
    _observe();
  }

  void _observe() {
    if (!_active || _disposed || _replacingQueue) return;
    final now = _clock.elapsedMilliseconds;
    final elapsed = _hearing
        ? Duration(milliseconds: now - _lastTick)
        : Duration.zero;
    final uri = _heardUri;
    final recorded = _history.advance(
      uri,
      elapsed,
      completed: player.processingState == ProcessingState.completed,
      durationMs: _heardDurationMs,
    );
    if (recorded != null) {
      _persist(() => store.record(recorded, DateTime.now()));
    }
    final currentTrack = audioTrackOf(player.sequenceState.currentSource);
    final current = currentTrack?.uri;
    // Natural repeat-one does not change the source, but starts a new listen.
    if (_completed &&
        player.processingState != ProcessingState.completed &&
        player.playing) {
      _history.restart();
    }
    _completed = player.processingState == ProcessingState.completed;
    if (current != uri) _history.advance(current, Duration.zero);
    _heardUri = current;
    _heardDurationMs = currentTrack?.durationMs ?? 0;
    _hearing =
        current != null &&
        player.playing &&
        player.processingState == ProcessingState.ready;
    _lastTick = now;
  }

  /// Prevent transient source/index events during queue replacement from
  /// entering history or overwriting the previous session.
  void beginQueueChange() {
    _observe();
    _replacingQueue = true;
    _hearing = false;
    _saveTimer?.cancel();
    _history.restart();
  }

  void endQueueChange() {
    _replacingQueue = false;
    _heardUri = null;
    if (player.sequence.isNotEmpty) _hasLoadedQueue = true;
    _observe();
    _scheduleSave();
  }

  void _scheduleSave() {
    if (!_active || _disposed || _replacingQueue) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(flush()),
    );
  }

  Future<void> _persist(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (!_disposed && !_reportedError) {
        _reportedError = true;
        onError();
      }
    }
  }

  Future<void> flush() async {
    if (!_active || _disposed || _replacingQueue) return;
    _lastSave = _clock.elapsedMilliseconds;
    final state = player.sequenceState;
    final tracks = state.sequence
        .map(audioTrackOf)
        .whereType<AudioTrack>()
        .toList();
    if (tracks.length != state.sequence.length) return;
    if (tracks.isEmpty && !_hasLoadedQueue) return;
    final session = PlaybackSession(
      uris: tracks.map((t) => t.uri),
      index: state.currentIndex ?? 0,
      positionMs: player.position.inMilliseconds.clamp(0, 1 << 53),
      shuffle: state.shuffleModeEnabled,
      order: state.shuffleIndices,
      loop: state.loopMode,
    );
    await _persist(() => store.saveSession(session));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _observe();
    unawaited(flush());
  }

  void dispose() {
    _observe();
    unawaited(flush());
    _disposed = true;
    _tick?.cancel();
    _saveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    _clock.stop();
  }
}
