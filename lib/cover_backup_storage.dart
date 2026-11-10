import 'dart:typed_data';

/// A snapshot uses opaque SHA-256 filenames, never paths or credentials.
abstract class CoverBackupStorage {
  Future<Map<String, Uint8List>> snapshot();
  Future<void> validateSnapshot(Map<String, Uint8List> images);
  Future<void> replaceSnapshot(Map<String, Uint8List> images);
}

const maxCoverBackupBytes = 24 * 1024 * 1024;
const maxCoverBackupCount = 1000;
final coverBackupKeyPattern = RegExp(r'^[0-9a-f]{64}$');

void validateCoverBackupShape(Map<String, Uint8List> images) {
  if (images.length > maxCoverBackupCount) {
    throw const FormatException('Too many covers');
  }
  var total = 0;
  for (final entry in images.entries) {
    if (!coverBackupKeyPattern.hasMatch(entry.key) ||
        entry.value.isEmpty ||
        entry.value.length > 10 * 1024 * 1024) {
      throw const FormatException('Invalid cover');
    }
    total += entry.value.length;
    if (total > maxCoverBackupBytes) {
      throw const FormatException('Covers too large');
    }
  }
}
