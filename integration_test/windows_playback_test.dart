import 'package:aura/audio_runtime.dart';
import 'package:aura/audio_features.dart';
import 'package:aura/audio_track.dart';
import 'package:audio_service/audio_service.dart';

import 'dart:io';

import 'package:aura/playback_settings_controller.dart';
import 'package:aura/saved_music.dart';

import '../test/support/memory_saved_music_storage.dart';

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows secure storage roundtrip for server credentials', (
    tester,
  ) async {
    const storage = FlutterSecureStorage();
    final key = 'aura_test_${DateTime.now().microsecondsSinceEpoch}';
    try {
      await storage.write(key: key, value: 'synthetic test value');
      expect(await storage.read(key: key), 'synthetic test value');
    } finally {
      await storage.delete(key: key);
    }
  });
  testWidgets('Windows native backend plays, seeks and changes queue entries', (
    tester,
  ) async {
    await Directory.systemTemp.create(recursive: true);
    final directory = await Directory.systemTemp.createTemp('aura-playback-');
    final store = SavedMusicStore(MemorySavedMusicStorage());
    await store.load();
    final runtime = AuraAudioRuntime(store);
    final player = runtime.player;
    await runtime.initializeService();
    PlaybackSettingsController? controls;
    try {
      const sampleRate = 16000;
      const count = sampleRate * 6;
      final bytes = ByteData(44 + count * 2);
      void text(int offset, String value) {
        for (var i = 0; i < value.length; i++) {
          bytes.setUint8(offset + i, value.codeUnitAt(i));
        }
      }

      text(0, 'RIFF');
      bytes.setUint32(4, 36 + count * 2, Endian.little);
      text(8, 'WAVE');
      text(12, 'fmt ');
      bytes.setUint32(16, 16, Endian.little);
      bytes.setUint16(20, 1, Endian.little);
      bytes.setUint16(22, 1, Endian.little);
      bytes.setUint32(24, sampleRate, Endian.little);
      bytes.setUint32(28, sampleRate * 2, Endian.little);
      bytes.setUint16(32, 2, Endian.little);
      bytes.setUint16(34, 16, Endian.little);
      text(36, 'data');
      bytes.setUint32(40, count * 2, Endian.little);
      for (var i = 0; i < count; i++) {
        bytes.setInt16(
          44 + i * 2,
          (sin(i * 2 * pi * 440 / sampleRate) * 1500).round(),
          Endian.little,
        );
      }
      final file = await File('${directory.path}/Aura test.wav')
          .writeAsBytes(bytes.buffer.asUint8List());
      await store.setPlaybackPreferences(volume: .05);
      await player.setVolume(0.05);
      await player.setAudioSources([
        AudioSource.file(
          file.path,
          tag: AudioTrack(
            id: 'one',
            uri: Uri.file(file.path).toString(),
            title: 'Synthetic one',
            artist: '',
            album: '',
            durationMs: 6000,
          ).toMediaItem(),
        ),
        AudioSource.file(
          file.path,
          tag: AudioTrack(
            id: 'two',
            uri: Uri.file(file.path).toString(),
            title: 'Synthetic two',
            artist: '',
            album: '',
            durationMs: 6000,
          ).toMediaItem(),
        ),
      ]);
      expect(player.duration!.inMilliseconds, closeTo(6000, 100));
      if (runtime.isAndroid) {
        final parameters = await runtime.equalizerParameters();
        expect(parameters, isNotNull);
        expect(parameters!.bands, isNotEmpty);
        final gains = List<double>.filled(parameters.bands.length, 0);
        gains[0] = 3.0.clamp(parameters.minDecibels, parameters.maxDecibels);
        await runtime.changeFeatures(
          AudioFeatures(equalizerEnabled: true, bandGains: gains),
        );
        expect(runtime.equalizer!.enabled, isTrue);
        expect(parameters.bands.first.gain, gains[0]);
        await runtime.changeFeatures(const AudioFeatures());
      }
      final playing = player.play();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      expect(
        player.playing,
        isTrue,
        reason:
            'state=${player.processingState}, position=${player.position}, duration=${player.duration}',
      );
      expect(player.position.inMilliseconds, greaterThan(100));
      await player.pause();
      expect(player.playing, isFalse);
      await player.seek(const Duration(milliseconds: 1200));
      expect(player.position.inMilliseconds, closeTo(1200, 250));
      await player.seekToNext();
      await player.currentIndexStream
          .firstWhere((index) => index == 1)
          .timeout(const Duration(seconds: 5));
      expect(player.currentIndex, 1);
      await player.setLoopMode(LoopMode.all);
      await player.setShuffleModeEnabled(true);
      expect(player.loopMode, LoopMode.all);
      expect(player.shuffleModeEnabled, isTrue);
      await store.load();
      await store.setPlaybackPreferences(volume: .03);
      controls = PlaybackSettingsController(
        player: player,
        store: store,
        onError: () => fail('Playback control error'),
      );
      await controls.change(speed: 1.25, volume: .03);
      expect(player.speed, 1.25);
      expect(player.volume, .03);
      expect(store.data.playbackSpeed, 1.25);
      await controls.change(speed: 1);
      await player.setShuffleModeEnabled(false);
      await player.setLoopMode(LoopMode.off);
      await runtime.changeFeatures(const AudioFeatures(crossfadeSeconds: 1));
      await player.seek(const Duration(milliseconds: 4500), index: 0);
      final overlappingPlayback = player.play();
      await player.volumeStream
          .firstWhere((gain) => gain < .029)
          .timeout(const Duration(seconds: 5));
      expect(runtime.transitioning, isTrue);
      expect(runtime.incomingPlaying, isTrue);
      expect(player.volume, lessThan(.03));
      await player.currentIndexStream
          .firstWhere((index) => index == 1)
          .timeout(const Duration(seconds: 6));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      expect(player.position.inMilliseconds, greaterThan(400));
      expect(runtime.incomingPlaying, isFalse);
      await player.pause();
      await overlappingPlayback;
      await runtime.changeFeatures(
        const AudioFeatures(seekButtons: true, headsetSeek: true),
      );
      final handler = AuraMediaHandler(runtime);
      await player.seek(const Duration(milliseconds: 1200), index: 1);
      await handler.click(MediaButton.previous);
      expect(player.currentIndex, 1);
      expect(player.position.inMilliseconds, lessThan(200));
      expect(
        handler.playbackState.value.controls.map((control) => control.action),
        contains(MediaAction.rewind),
      );
      await runtime.changeFeatures(const AudioFeatures());
      await handler.click(MediaButton.previous);
      expect(player.currentIndex, 0);
      expect(player.playing, isFalse);
      await runtime.changeFeatures(const AudioFeatures(fadeMilliseconds: 250));
      await runtime.play();
      expect(player.playing, isTrue);
      expect(player.volume, closeTo(.03, .001));
      await runtime.pause();
      expect(player.playing, isFalse);
      await runtime.changeFeatures(const AudioFeatures());
      controls.sleep.start(const Duration(milliseconds: 100));
      final timerPlayback = player.play();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 1400)),
      );
      expect(player.playing, isFalse);
      expect(controls.sleep.active, isFalse);
      await timerPlayback;
      await player.stop();
      await playing;
    } finally {
      controls?.dispose();
      store.dispose();
      await runtime.dispose();
      await directory.delete(recursive: true);
    }
  });
}
