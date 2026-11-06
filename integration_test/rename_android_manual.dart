import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const TestApp());

class TestApp extends StatefulWidget {
  const TestApp({super.key});
  @override
  State<TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<TestApp> {
  static const channel = MethodChannel(
    'com.example.symphonium_clone/audio_library',
  );
  static const uri = String.fromEnvironment('AURA_TEST_URI');
  static const before = String.fromEnvironment('AURA_TEST_BEFORE');
  static const after = String.fromEnvironment('AURA_TEST_AFTER');
  String status = 'Starting';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => run());
  }

  Future<void> run() async {
    try {
      if (uri.isEmpty || before.isEmpty || after.isEmpty) {
        throw StateError('Missing fixture');
      }
      if (await channel.invokeMethod<bool>('requestSyntheticReadPermission') !=
          true) {
        throw StateError('Read denied');
      }
      if (await channel.invokeMethod<String>('getAudioFileName', {
            'uri': uri,
          }) !=
          before) {
        throw StateError('Initial name mismatch');
      }
      if (await channel.invokeMethod<bool>('renameAudioFile', {
            'uri': uri,
            'name': after,
          }) !=
          true) {
        throw StateError('Rename denied');
      }
      if (await channel.invokeMethod<String>('getAudioFileName', {
            'uri': uri,
          }) !=
          '$after.wav') {
        throw StateError('Final name mismatch');
      }
      if (mounted) setState(() => status = 'TEST PASSED');
    } catch (e) {
      if (mounted) setState(() => status = 'TEST FAILED: $e');
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(body: Center(child: Text(status))),
  );
}
