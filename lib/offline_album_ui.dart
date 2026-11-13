import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'app_strings.dart';
import 'audio_track.dart';
import 'offline_storage.dart';
import 'download_network_policy.dart';
import 'audio_library.dart';
import 'background_downloads_ui.dart';

enum OfflineDownloadGroup { album, playlist, artist, genre }

String _downloadLabel(BuildContext context, OfflineDownloadGroup group) =>
    switch (group) {
      OfflineDownloadGroup.album => context.appStrings.offlineAlbumDownload,
      OfflineDownloadGroup.playlist =>
        context.appStrings.offlinePlaylistDownload,
      OfflineDownloadGroup.artist => context.appStrings.offlineArtistDownload,
      OfflineDownloadGroup.genre => context.appStrings.offlineGenreDownload,
    };

String _downloadNotice(BuildContext context, OfflineDownloadGroup group) =>
    switch (group) {
      OfflineDownloadGroup.album => context.appStrings.offlineAlbumNotice,
      OfflineDownloadGroup.playlist => context.appStrings.offlinePlaylistNotice,
      OfflineDownloadGroup.artist => context.appStrings.offlineArtistNotice,
      OfflineDownloadGroup.genre => context.appStrings.offlineGenreNotice,
    };

class OfflineAlbumAction extends StatelessWidget {
  const OfflineAlbumAction({
    super.key,
    required this.store,
    required this.tracks,
    this.group = OfflineDownloadGroup.album,
  });
  final OfflineStorage store;
  final List<AudioTrack> tracks;
  final OfflineDownloadGroup group;

  @override
  Widget build(BuildContext context) {
    final unique = <String, AudioTrack>{};
    for (final track in tracks) {
      final uri = Uri.tryParse(track.uri);
      if (uri?.scheme == 'aura' &&
          uri?.host == 'navidrome' &&
          uri!.pathSegments.length == 2) {
        unique.putIfAbsent(track.uri, () => track);
      }
    }
    if (unique.isEmpty) return const SizedBox.shrink();
    return OutlinedButton.icon(
      key: ValueKey('offline-${group.name}-action'),
      icon: const Icon(Icons.download_outlined),
      label: Text(_downloadLabel(context, group)),
      onPressed: () => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AlbumDownloadDialog(
          store: store,
          tracks: unique.values.toList(),
          group: group,
          onBackground:
              !kIsWeb &&
                  defaultTargetPlatform == TargetPlatform.android &&
                  identical(store, AudioLibrary.offline)
              ? () {
                  Navigator.of(context).pop();
                  if (context.mounted) {
                    openBackgroundDownloads(context, unique.values.toList());
                  }
                }
              : null,
        ),
      ),
    );
  }
}

class _AlbumDownloadDialog extends StatefulWidget {
  const _AlbumDownloadDialog({
    required this.store,
    required this.tracks,
    required this.group,
    this.onBackground,
  });
  final OfflineStorage store;
  final List<AudioTrack> tracks;
  final OfflineDownloadGroup group;
  final VoidCallback? onBackground;
  @override
  State<_AlbumDownloadDialog> createState() => _AlbumDownloadDialogState();
}

class _AlbumDownloadDialogState extends State<_AlbumDownloadDialog> {
  bool started = false,
      running = false,
      stopRequested = false,
      networkBlocked = false;
  int done = 0, failed = 0;

  Future<void> start() async {
    setState(() {
      started = true;
      running = true;
    });
    for (final track in widget.tracks) {
      if (stopRequested) break;
      try {
        await widget.store.download(track);
      } on DownloadNetworkException {
        networkBlocked = true;
        break;
      } catch (_) {
        failed++;
      }
      done++;
      if (mounted) setState(() {});
    }
    if (mounted) setState(() => running = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.appStrings;
    return PopScope(
      canPop: !running,
      child: AlertDialog(
        title: Text(_downloadLabel(context, widget.group)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_downloadNotice(context, widget.group)),
              if (widget.onBackground != null) ...[
                const SizedBox(height: 12),
                Text(s.backgroundNotice),
              ],
              const SizedBox(height: 12),
              Text('${s.offlineAlbumTracks}: ${widget.tracks.length}'),
              if (started) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: done / widget.tracks.length),
                const SizedBox(height: 8),
                Text(
                  '${s.offlineAlbumProgress}: $done / ${widget.tracks.length}',
                ),
                if (networkBlocked) Text(s.offlineNetworkBlocked),
                if (failed > 0) Text('${s.offlineAlbumFailed}: $failed'),
                if (stopRequested && running) Text(s.offlineAlbumStopping),
                if (!running && !networkBlocked)
                  Text(
                    stopRequested
                        ? s.offlineAlbumStopped
                        : s.offlineAlbumFinished,
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('offline-album-cancel'),
            onPressed: running
                ? stopRequested
                      ? null
                      : () => setState(() => stopRequested = true)
                : () => Navigator.pop(context),
            child: Text(running ? s.uiCancel : s.uiClose),
          ),
          if (!started && widget.onBackground != null)
            TextButton(
              key: const ValueKey('offline-background-action'),
              onPressed: widget.onBackground,
              child: Text(s.backgroundButton),
            ),
          if (!started)
            FilledButton(
              key: const ValueKey('offline-album-confirm'),
              onPressed: start,
              child: Text(_downloadLabel(context, widget.group)),
            ),
        ],
      ),
    );
  }
}
