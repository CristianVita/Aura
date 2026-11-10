import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'album_artwork.dart';
import 'app_strings.dart';
import 'cover_lookup_screen.dart';

enum _CoverAction { file, photos, online, remove }

class AlbumCoverButton extends StatelessWidget {
  const AlbumCoverButton({super.key, required this.album, this.searchTitle});
  final String album;
  final String? searchTitle;

  Future<void> _apply(BuildContext context, _CoverAction action) async {
    if (action == _CoverAction.online) {
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => CoverLookupScreen(
            albumKey: album,
            initialTitle: searchTitle ?? album,
          ),
        ),
      );
      if (saved == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.appStrings.albumCoverSaved)),
        );
      }
      return;
    }
    final remove = action == _CoverAction.remove;
    final strings = context.appStrings;
    try {
      if (remove) {
        await albumArtwork.remove(album);
      } else {
        final files = await FilePicker.pickFiles(
          type: action == _CoverAction.photos
              ? FileType.image
              : FileType.custom,
          allowedExtensions: action == _CoverAction.photos
              ? null
              : ['jpg', 'jpeg', 'png', 'webp'],
          dialogTitle: strings.albumCoverChoose,
        );
        if (files.isEmpty) return;
        final file = files.single;
        final length = await file.length();
        if (length != null && length > AlbumArtworkStore.maxInputBytes) {
          throw const FormatException('Image too large');
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in file.readAsByteStream()) {
          if (builder.length + chunk.length > AlbumArtworkStore.maxInputBytes) {
            throw const FormatException('Image too large');
          }
          builder.add(chunk);
        }
        await albumArtwork.set(album, builder.takeBytes());
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              remove ? strings.albumCoverRemoved : strings.albumCoverSaved,
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(strings.albumCoverError)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<_CoverAction>(
    tooltip: context.appStrings.albumCoverChoose,
    icon: const Icon(Icons.add_photo_alternate_outlined),
    onSelected: (action) => _apply(context, action),
    itemBuilder: (context) => [
      PopupMenuItem(
        value: _CoverAction.file,
        child: Text(context.appStrings.albumCoverChoose),
      ),
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        PopupMenuItem(
          value: _CoverAction.photos,
          child: Text(context.appStrings.albumCoverPhotos),
        ),
      PopupMenuItem(
        value: _CoverAction.online,
        child: Text(context.appStrings.coverOnlineTitle),
      ),
      PopupMenuItem(
        value: _CoverAction.remove,
        child: Text(context.appStrings.albumCoverRemove),
      ),
    ],
  );
}
