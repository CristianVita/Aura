import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import 'saved_music.dart';
import 'sleep_timer.dart';

class PlaybackSettingsController with WidgetsBindingObserver {
  PlaybackSettingsController({
    required this.player,
    required this.store,
    required this.onError,
  }) {
    sleep = SleepTimerController(
      pause: player.pause,
      isPlaying: () =>
          player.playing && player.processingState != ProcessingState.completed,
      onError: onError,
    );
    store.addListener(_restoreOnce);
    WidgetsBinding.instance.addObserver(this);
    _subscriptions.add(
      player.positionDiscontinuityStream.listen((event) {
        if (event.reason == PositionDiscontinuityReason.autoAdvance) {
          sleep.onTrackEnded();
        }
      }),
    );
    _subscriptions.add(
      player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) sleep.onTrackEnded();
      }),
    );
    _restoreOnce();
  }
  final AudioPlayer player;
  final SavedMusicStore store;
  final VoidCallback onError;
  late final SleepTimerController sleep;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Future<void> _pending = Future.value();
  bool _restored = false;
  bool _disposed = false;
  void _restoreOnce() {
    if (!store.ready || _restored || _disposed) return;
    _restored = true;
    _pending = _apply(store.data.playbackSpeed, store.data.playbackVolume)
        .catchError((Object _) {
          if (!_disposed) onError();
        });
  }

  Future<void> _apply(double speed, double volume) async {
    if (_disposed) return;
    await player.setVolume(volume);
    await player.setSpeed(speed);
  }

  Future<void> change({double? speed, double? volume}) {
    if ((speed != null && (!speed.isFinite || speed < .5 || speed > 2)) ||
        (volume != null && (!volume.isFinite || volume < 0 || volume > 1))) {
      return Future.error(ArgumentError('Invalid playback setting'));
    }
    final operation = _pending.then((_) async {
      if (_disposed || !store.ready) {
        throw StateError('Playback settings unavailable');
      }
      final previous = store.data;
      try {
        await _apply(
          speed ?? previous.playbackSpeed,
          volume ?? previous.playbackVolume,
        );
        await store.setPlaybackPreferences(speed: speed, volume: volume);
      } catch (_) {
        await _apply(previous.playbackSpeed, previous.playbackVolume);
        rethrow;
      }
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) sleep.checkDeadline();
  }

  void dispose() {
    _disposed = true;
    store.removeListener(_restoreOnce);
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    sleep.dispose();
  }
}
