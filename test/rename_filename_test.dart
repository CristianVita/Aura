import 'package:aura/rename_filename.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('renaming keeps the original audio extension', () {
    expect(renamedAudioFilename('old.MP3', 'New name'), 'New name.MP3');
    expect(
      renamedAudioFilename('old.flac', 'Björk - Jóga'),
      'Björk - Jóga.flac',
    );
  });
  test('invalid names and path traversal are rejected', () {
    for (final value in [
      '',
      '.',
      '..',
      'folder/name',
      r'folder\name',
      'CON',
      'LPT1.txt',
      'bad?',
      'trailing.',
      'x' * 256,
    ]) {
      expect(
        () => renamedAudioFilename('track.mp3', value),
        throwsFormatException,
        reason: value,
      );
    }
    expect(
      () => renamedAudioFilename('extensionless', 'ok'),
      throwsFormatException,
    );
  });
}
