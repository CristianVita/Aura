import 'package:aura/audio_track.dart';
import 'package:aura/library_catalog.dart';
import 'package:aura/library_preferences.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';

class MemoryStorage implements SavedMusicStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String json) async {
    value = json;
  }
}

void main() => runApp(const TestApp());

class TestApp extends StatefulWidget {
  const TestApp({super.key});
  @override
  State<TestApp> createState() => TestState();
}

class TestState extends State<TestApp> {
  String status = 'Starting sort test';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => run());
  }

  Future<void> run() async {
    final disk = MemoryStorage();
    final store = SavedMusicStore(disk);
    try {
      await store.load();
      final rows = [
        {
          'id': 'a',
          'title': 'Later',
          'artist': 'B',
          'album': 'Y',
          'durationMs': 4000,
          'year': 2001,
          'uri': 'file:///synthetic-a',
        },
        {
          'id': 'b',
          'title': 'Earlier',
          'artist': 'A',
          'album': 'X',
          'durationMs': 1000,
          'year': 1990,
          'uri': 'file:///synthetic-b',
        },
        {
          'id': 'c',
          'title': 'Unknown',
          'artist': '',
          'album': '',
          'durationMs': 0,
          'uri': 'file:///synthetic-c',
        },
      ].map(AudioTrack.fromMap).toList();
      final years = sortLibraryTracks(
        rows,
        TrackSort.year,
      ).map((track) => track.id).join(',');
      final artists = sortLibraryTracks(
        rows,
        TrackSort.artist,
      ).map((track) => track.id).join(',');
      await store.setLibraryPages(
        store.data.libraryPages.copy(trackSort: TrackSort.year),
      );
      if (years != 'b,a,c' ||
          artists != 'b,a,c' ||
          SavedMusicData.decode(disk.value!).libraryPages.trackSort !=
              TrackSort.year) {
        throw StateError('Sort mismatch');
      }
      if (mounted) setState(() => status = 'TRACK SORT TEST PASSED');
    } catch (error) {
      if (mounted) setState(() => status = 'TRACK SORT TEST FAILED: $error');
    } finally {
      store.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(body: Center(child: Text(status))),
  );
}
