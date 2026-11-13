import 'app_language.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_features.dart';
import 'audio_sources.dart';
import 'audio_track.dart';
import 'saved_music.dart';

AudioSessionConfiguration musicSessionConfiguration({
  required bool isAndroid,
  required bool pauseWhenDucked,
}) {
  const music = AudioSessionConfiguration.music();
  return isAndroid && pauseWhenDucked
      ? music.copyWith(androidWillPauseWhenDucked: true)
      : music;
}

MediaControl localizedMediaControl(MediaControl control) {
  final strings = AppText.current;
  return control.copyWith(
    label: switch (control.action) {
      MediaAction.play => strings.previewButton,
      MediaAction.pause => strings.uiPause,
      MediaAction.stop => strings.mediaStop,
      MediaAction.skipToPrevious => strings.uiPreviousTrack,
      MediaAction.skipToNext => strings.uiNextTrack,
      MediaAction.rewind => strings.mediaSeekBack,
      MediaAction.fastForward => strings.mediaSeekForward,
      _ => control.label,
    },
  );
}

/// The main queue remains authoritative; the second decoder renders the head
/// of the next track during an overlap and hands it back at the same position.
class AuraAudioRuntime {
  AuraAudioRuntime(this.store, {bool? android})
    : isAndroid =
          android ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    equalizer = isAndroid ? AndroidEqualizer() : null;
    player = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [?equalizer]),
    );
    _subscriptions.add(
      player.positionDiscontinuityStream.listen(_discontinuity),
    );
    _subscriptions.add(
      player.playerStateStream.listen((state) {
        _syncTicker();
        if (!state.playing ||
            (!(_handoff) &&
                state.processingState == ProcessingState.buffering)) {
          unawaited(cancelTransition());
        }
        if (state.processingState == ProcessingState.ready) {
          unawaited(_restoreEffects());
        }
      }),
    );
    _subscriptions.add(
      player.speedStream.listen((speed) {
        if (_overlapping) unawaited(_incoming?.setSpeed(speed));
      }),
    );
    store.addListener(_preferencesChanged);
    _syncTicker();
  }
  final SavedMusicStore store;
  final bool isAndroid;
  late final AudioPlayer player;
  late final AndroidEqualizer? equalizer;
  AudioPlayer? _incoming;
  AuraMediaHandler? _handler;
  AndroidEqualizer? _incomingEqualizer;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _ticker;
  IndexedAudioSource? _outgoingSource;
  int? _targetIndex;
  String? _targetUri;
  bool _preparing = false,
      _overlapping = false,
      _handoff = false,
      _tickBusy = false,
      _disposed = false;
  int _generation = 0, _fadeGeneration = 0;
  String? _effectsKey;
  bool _effectsBusy = false;
  Completer<void>? _effectsCompletion;
  double _lastPrimaryGain = -1;
  bool Function()? allowCrossfade;
  bool get incomingPlaying => _incoming?.playing ?? false;
  bool get transitioning => _overlapping || _handoff;
  AudioFeatures get features => store.data.audioFeatures;
  double get baseVolume {
    final positive = features.equalizerEnabled && isAndroid
        ? features.bandGains.fold<double>(0, (a, b) => math.max(a, b))
        : 0.0;
    return store.data.playbackVolume * math.pow(10, -positive / 20);
  }

  Future<void> refreshOutputGain() => _gain(player, baseVolume);

  Future<void> applyStoredAudioPreferences() async {
    await cancelTransition();
    await _restoreEffects(reportErrors: true);
    await refreshOutputGain();
  }

  Future<void> initializeService() async {
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      await AudioService.init<AuraMediaHandler>(
        builder: () => _handler = AuraMediaHandler(this),
        config: AudioServiceConfig(
          androidNotificationChannelId: 'com.example.symphonium_clone.playback',
          androidNotificationChannelName: AppText.current.uiAudioPlayback,
          androidNotificationIcon: 'drawable/ic_stat_audio',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
      final session = await AudioSession.instance;
      await session.configure(
        musicSessionConfiguration(
          isAndroid: isAndroid,
          pauseWhenDucked: features.pauseWhenDucked,
        ),
      );
    }
  }

  void _syncTicker() {
    if (_disposed) return;
    if (player.playing && features.crossfadeSeconds > 0) {
      _ticker ??= Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => unawaited(_tick()),
      );
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _preferencesChanged() {
    _syncTicker();
    if (features.crossfadeSeconds == 0 && transitioning) {
      unawaited(cancelTransition());
    }
    unawaited(_restoreEffects());
    if (!transitioning && _fadeGeneration == 0) {
      unawaited(_gain(player, baseVolume));
    }
  }

  Future<AndroidEqualizerParameters?> equalizerParameters() async {
    if (equalizer == null || player.processingState == ProcessingState.idle) {
      return null;
    }
    return equalizer!.parameters.timeout(const Duration(seconds: 5));
  }

  Future<void> _applyEqualizer(
    AndroidEqualizer effect,
    AudioFeatures value,
  ) async {
    final parameters = await effect.parameters.timeout(
      const Duration(seconds: 5),
    );
    for (final band in parameters.bands) {
      final gain = band.index < value.bandGains.length
          ? value.bandGains[band.index]
          : 0.0;
      await band.setGain(
        gain.clamp(parameters.minDecibels, parameters.maxDecibels),
      );
    }
    await effect.setEnabled(value.equalizerEnabled);
  }

  Future<void> changeFeatures(AudioFeatures next) async {
    // Validate before touching the decoder or durable settings.
    AudioFeatures.fromJson(next.toJson());
    final previous = features;
    try {
      if (equalizer != null && player.processingState != ProcessingState.idle) {
        await _applyEqualizer(equalizer!, next);
      }
      await store.setAudioFeatures(next);
    } catch (_) {
      if (equalizer != null && player.processingState != ProcessingState.idle) {
        await _applyEqualizer(equalizer!, previous);
      }
      rethrow;
    }
  }

  Future<void> _restoreEffects({bool reportErrors = false}) async {
    if (_disposed ||
        equalizer == null ||
        player.processingState != ProcessingState.ready) {
      return;
    }
    if (_effectsBusy) {
      await _effectsCompletion!.future;
      return _restoreEffects(reportErrors: reportErrors);
    }
    final key = '${features.equalizerEnabled}:${features.bandGains}';
    if (key == _effectsKey) return;
    _effectsBusy = true;
    final completion = _effectsCompletion = Completer<void>();
    var applied = false;
    try {
      await _applyEqualizer(equalizer!, features);
      _effectsKey = key;
      applied = true;
      if (!transitioning && _fadeGeneration == 0) {
        await _gain(player, baseVolume);
      }
    } catch (_) {
      if (reportErrors) rethrow;
    } finally {
      _effectsBusy = false;
      completion.complete();
    }
    if (applied &&
        key != '${features.equalizerEnabled}:${features.bandGains}') {
      await _restoreEffects(reportErrors: reportErrors);
    }
  }

  Future<void> _gain(AudioPlayer target, double gain) async {
    if (identical(target, player)) {
      if ((player.volume - gain).abs() < .001 &&
          (_lastPrimaryGain - gain).abs() < .001) {
        return;
      }
      _lastPrimaryGain = gain;
    }
    await target.setVolume(gain.clamp(0.0, 1.0));
  }

  Future<void> _tick() async {
    if (_disposed || _tickBusy || _handoff) return;
    _tickBusy = true;
    try {
      if (allowCrossfade?.call() == false) {
        if (_overlapping || _preparing) {
          await cancelTransition();
        }
        return;
      }
      if (_overlapping) {
        if (!player.playing ||
            player.sequenceState.currentSource != _outgoingSource) {
          return;
        }
        final duration = player.duration;
        if (duration == null) {
          await cancelTransition();
          return;
        }
        final remaining =
            (duration - player.position).inMilliseconds / 1000 / player.speed;
        final progress = (1 - remaining / features.crossfadeSeconds).clamp(
          0.0,
          1.0,
        );
        await _gain(player, baseVolume * math.cos(progress * math.pi / 2));
        if (_incoming != null) {
          await _gain(
            _incoming!,
            baseVolume * math.sin(progress * math.pi / 2),
          );
        }
      } else if (_fadeGeneration == 0) {
        if (_lastPrimaryGain < 0) await _gain(player, baseVolume);
        if (_preparing ||
            features.crossfadeSeconds == 0 ||
            !player.playing ||
            player.processingState != ProcessingState.ready ||
            player.loopMode == LoopMode.one) {
          return;
        }
        final duration = player.duration, next = player.nextIndex;
        if (duration == null ||
            next == null ||
            duration.inSeconds < features.crossfadeSeconds * 2) {
          return;
        }
        final remaining =
            (duration - player.position).inMilliseconds / 1000 / player.speed;
        if (remaining <= features.crossfadeSeconds && remaining > .25) {
          unawaited(_prepare(next));
        }
      }
    } catch (_) {
      await cancelTransition();
    } finally {
      _tickBusy = false;
    }
  }

  Future<void> _prepare(int index) async {
    _preparing = true;
    final generation = ++_generation;
    final source = player.sequenceState.currentSource;
    final track = audioTrackOf(player.sequence[index]);
    try {
      if (track == null ||
          (track.durationMs > 0 &&
              track.durationMs < features.crossfadeSeconds * 2000)) {
        return;
      }
      if (_incoming == null) {
        _incomingEqualizer = isAndroid ? AndroidEqualizer() : null;
        _incoming = AudioPlayer(
          handleInterruptions: false,
          handleAudioSessionActivation: false,
          audioPipeline: AudioPipeline(
            androidAudioEffects: [?_incomingEqualizer],
          ),
        );
      }
      await _incoming!.setVolume(0);
      await _incoming!.setSpeed(player.speed);
      await _incoming!.setAudioSource(await sourceForTrack(track));
      if (_incomingEqualizer != null) {
        await _applyEqualizer(_incomingEqualizer!, features);
      }
      if (_disposed ||
          generation != _generation ||
          !player.playing ||
          player.sequenceState.currentSource != source ||
          player.nextIndex != index ||
          features.crossfadeSeconds == 0) {
        return;
      }
      _targetIndex = index;
      _targetUri = track.uri;
      _outgoingSource = source;
      _overlapping = true;
      unawaited(_incoming!.play().catchError((Object _) => cancelTransition()));
    } catch (_) {
      await cancelTransition();
    } finally {
      _preparing = false;
    }
  }

  void _discontinuity(PositionDiscontinuity event) {
    if (_handoff) return;
    // Discontinuity is emitted before just_audio updates currentIndex and
    // sequenceState. Resolve the target from the event, not stale getters.
    final index = event.event.currentIndex;
    final current =
        index != null && index >= 0 && index < player.sequence.length
        ? audioTrackOf(player.sequence[index])
        : null;
    if (event.reason == PositionDiscontinuityReason.autoAdvance &&
        _overlapping &&
        index == _targetIndex &&
        current?.uri == _targetUri) {
      unawaited(_completeHandoff());
    } else if (_preparing || _overlapping) {
      unawaited(cancelTransition());
    }
  }

  Future<void> _completeHandoff() async {
    _handoff = true;
    final generation = _generation;
    final target = _targetIndex;
    try {
      await player.currentIndexStream
          .firstWhere((index) => index == target)
          .timeout(const Duration(seconds: 2));
      if (!player.playing || _incoming == null) return;
      await _gain(player, 0);
      // Seek while the incoming decoder continues rendering, then transfer
      // gain over a short overlap rather than cutting the second decoder.
      await player.seek(_incoming!.position);
      for (var step = 1; step <= 5; step++) {
        if (_disposed || generation != _generation || !player.playing) return;
        await _gain(player, baseVolume * step / 5);
        await _gain(_incoming!, baseVolume * (1 - step / 5));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } catch (_) {
      /* Fall back to the authoritative queue. */
    } finally {
      _handoff = false;
      await cancelTransition();
    }
  }

  Future<void> cancelTransition() async {
    _generation++;
    _overlapping = false;
    _outgoingSource = null;
    _targetIndex = null;
    _targetUri = null;
    if (_incoming != null) {
      await _incoming!.pause();
      await _incoming!.setVolume(0);
    }
    if (!_disposed && _fadeGeneration == 0) await _gain(player, baseVolume);
  }

  Future<void> play() async {
    if (player.processingState == ProcessingState.completed) {
      await player.seek(Duration.zero);
    }
    final milliseconds = features.fadeMilliseconds;
    if (milliseconds == 0) {
      unawaited(player.play().catchError((Object _) {}));
      return;
    }
    final token = ++_fadeGeneration;
    await _gain(player, 0);
    unawaited(player.play().catchError((Object _) {}));
    await _fade(token, milliseconds, true);
  }

  Future<void> pause() async {
    await cancelTransition();
    if (!player.playing || features.fadeMilliseconds == 0) {
      await player.pause();
      return;
    }
    final token = ++_fadeGeneration;
    await _fade(token, features.fadeMilliseconds, false);
    if (_fadeGeneration == 0) await player.pause();
    await _gain(player, baseVolume);
  }

  Future<void> _fade(int token, int milliseconds, bool fadeIn) async {
    for (var step = 1; step <= 20; step++) {
      if (_disposed || token != _fadeGeneration) return;
      await _gain(player, baseVolume * (fadeIn ? step / 20 : 1 - step / 20));
      await Future<void>.delayed(Duration(milliseconds: milliseconds ~/ 20));
    }
    if (token == _fadeGeneration) _fadeGeneration = 0;
  }

  Future<void> skip(bool next) async {
    await cancelTransition();
    final paused = !player.playing;
    if (next ? player.hasNext : player.hasPrevious) {
      await (next ? player.seekToNext() : player.seekToPrevious());
      if (paused && !features.keepPausedOnSkip) await play();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _handler?.detachLocale();
    _generation++;
    _fadeGeneration++;
    _ticker?.cancel();
    store.removeListener(_preferencesChanged);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _incoming?.dispose();
    await player.dispose();
  }
}

class AuraMediaHandler extends BaseAudioHandler {
  AuraMediaHandler(this.runtime) {
    runtime.player.playbackEventStream.listen(
      (_) => _broadcast(),
      onError: (Object _, StackTrace stack) {
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            errorCode: 1,
            errorMessage: AppText.current.uiPlaybackIsUnavailable,
          ),
        );
      },
    );
    runtime.player.playerStateStream.listen((_) => _broadcast());
    runtime.player.sequenceStateStream.listen((_) => _broadcast());
    runtime.store.addListener(_broadcast);
    AppText.changes.addListener(_broadcast);
    _broadcast();
  }
  final AuraAudioRuntime runtime;
  void detachLocale() {
    AppText.changes.removeListener(_broadcast);
    runtime.store.removeListener(_broadcast);
  }

  AudioPlayer get player => runtime.player;
  void _broadcast() {
    final tracks = player.sequence
        .map(audioTrackOf)
        .whereType<AudioTrack>()
        .map((t) => runtime.store.data.displayTrack(t).toMediaItem())
        .toList();
    if (queue.value.length != tracks.length ||
        !listEquals(
          queue.value.map((t) => (t.id, t.title)).toList(),
          tracks.map((t) => (t.id, t.title)).toList(),
        )) {
      queue.add(tracks);
    }
    final currentTrack = audioTrackOf(player.sequenceState.currentSource);
    final current = currentTrack == null
        ? null
        : runtime.store.data.displayTrack(currentTrack).toMediaItem();
    if (current != null) {
      mediaItem.add(
        current.copyWith(duration: player.duration ?? current.duration),
      );
    }
    final controls = <MediaControl>[
      if (runtime.features.seekButtons)
        MediaControl.rewind
      else if (player.hasPrevious)
        MediaControl.skipToPrevious,
      player.playing ? MediaControl.pause : MediaControl.play,
      if (runtime.features.seekButtons)
        MediaControl.fastForward
      else if (player.hasNext)
        MediaControl.skipToNext,
      if (runtime.features.showStop) MediaControl.stop,
    ];
    playbackState.add(
      playbackState.value.copyWith(
        controls: controls.map(localizedMediaControl).toList(growable: false),
        androidCompactActionIndices: List.generate(
          math.min(3, controls.length),
          (index) => index,
        ),
        systemActions: {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setRepeatMode,
          MediaAction.setShuffleMode,
        },
        processingState: switch (player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing:
            player.playing &&
            player.processingState != ProcessingState.completed,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: player.currentIndex,
        repeatMode: switch (player.loopMode) {
          LoopMode.off => AudioServiceRepeatMode.none,
          LoopMode.one => AudioServiceRepeatMode.one,
          LoopMode.all => AudioServiceRepeatMode.all,
        },
        shuffleMode: player.shuffleModeEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  @override
  Future<void> play() => runtime.play();
  @override
  Future<void> pause() => runtime.pause();
  @override
  Future<void> stop() async {
    await runtime.cancelTransition();
    await player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await runtime.cancelTransition();
    await player.seek(position);
  }

  @override
  Future<void> skipToNext() => runtime.skip(true);
  @override
  Future<void> skipToPrevious() => runtime.skip(false);
  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= player.sequence.length) return;
    await runtime.cancelTransition();
    await player.seek(Duration.zero, index: index);
  }

  Future<void> _relative(int seconds) => seek(
    Duration(
      milliseconds: (player.position.inMilliseconds + seconds * 1000).clamp(
        0,
        player.duration?.inMilliseconds ?? 0,
      ),
    ),
  );
  @override
  Future<void> fastForward() => _relative(10);
  @override
  Future<void> rewind() => _relative(-10);
  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    if (button == MediaButton.media) {
      if (player.playing) {
        await pause();
      } else {
        await play();
      }
    } else if (runtime.features.headsetSeek) {
      if (button == MediaButton.next) {
        await fastForward();
      } else {
        await rewind();
      }
    } else {
      if (button == MediaButton.next) {
        await skipToNext();
      } else {
        await skipToPrevious();
      }
    }
  }

  @override
  Future<void> setSpeed(double speed) => player.setSpeed(speed);
  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      player.setLoopMode(switch (repeatMode) {
        AudioServiceRepeatMode.one => LoopMode.one,
        AudioServiceRepeatMode.all ||
        AudioServiceRepeatMode.group => LoopMode.all,
        _ => LoopMode.off,
      });
  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (shuffleMode != AudioServiceShuffleMode.none) await player.shuffle();
    await player.setShuffleModeEnabled(
      shuffleMode != AudioServiceShuffleMode.none,
    );
  }
}
