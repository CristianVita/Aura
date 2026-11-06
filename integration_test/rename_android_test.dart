import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.symphonium_clone/audio_library');
  const uri = String.fromEnvironment('AURA_TEST_URI');
  const before = String.fromEnvironment('AURA_TEST_BEFORE');
  const after = String.fromEnvironment('AURA_TEST_AFTER');
  testWidgets('rename isolated synthetic audio', (tester) async {
    expect(uri, isNotEmpty);
    await tester.runAsync(() async {
      expect(
        await channel.invokeMethod<bool>('requestSyntheticReadPermission'),
        isTrue,
      );
      expect(
        await channel.invokeMethod<String>('getAudioFileName', {'uri': uri}),
        before,
      );
      expect(
        await channel.invokeMethod<bool>('renameAudioFile', {
          'uri': uri,
          'name': after,
        }),
        isTrue,
      );
      expect(
        await channel.invokeMethod<String>('getAudioFileName', {'uri': uri}),
        '$after.wav',
      );
    });
  });
}
