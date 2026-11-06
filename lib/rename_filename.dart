import 'package:path/path.dart' as p;

/// Accepts a new basename while retaining the original extension.
String renamedAudioFilename(String original, String basename) {
  final extension = p.extension(original);
  final stem = basename.trim();
  if (extension.isEmpty ||
      stem.isEmpty ||
      stem == '.' ||
      stem == '..' ||
      stem.endsWith('.') ||
      stem.endsWith(' ') ||
      stem.length + extension.length > 255 ||
      RegExp(r'[\\/<>:"|?*\x00-\x1f]').hasMatch(stem) ||
      RegExp(
        r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$',
        caseSensitive: false,
      ).hasMatch(stem)) {
    throw const FormatException('Invalid file name');
  }
  return '$stem$extension';
}
