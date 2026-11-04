import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'aura_backup.dart';

class PickedBackup {
  const PickedBackup(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

abstract class BackupFiles {
  Future<PickedBackup?> pick();
  Future<bool> save(String name, Uint8List bytes);
}

class DeviceBackupFiles implements BackupFiles {
  @override
  Future<PickedBackup?> pick() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Alege un backup Aura',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty) return null;
    final file = files.single;
    final length = await file.length();
    if (length != null && length > maxBackupBytes) {
      throw const FormatException('Backup too large');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      if (builder.length + chunk.length > maxBackupBytes) {
        throw const FormatException('Backup too large');
      }
      builder.add(chunk);
    }
    return PickedBackup(file.name, builder.takeBytes());
  }

  @override
  Future<bool> save(String name, Uint8List bytes) async =>
      await FilePicker.saveFile(
        fileName: name,
        bytes: bytes,
        mimeType: 'application/json',
        dialogTitle: 'Salvează backupul Aura',
      ) !=
      null;
}
