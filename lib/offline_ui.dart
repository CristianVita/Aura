import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'app_strings.dart';
import 'audio_track.dart';
import 'offline_storage.dart';
import 'download_network_policy.dart';
import 'audio_library.dart';
import 'background_downloads_ui.dart';

class OfflineTrackAction extends StatelessWidget {
  const OfflineTrackAction({
    super.key,
    required this.store,
    required this.track,
    this.onChanged,
    this.canRemove,
    this.onRemove,
    this.iconOnly = false,
  });
  final OfflineStorage store;
  final AudioTrack track;
  final VoidCallback? onChanged;
  final bool Function(String)? canRemove;
  final VoidCallback? onRemove;
  final bool iconOnly;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => FutureBuilder<bool>(
      future: store.hasRecord(track.uri),
      builder: (context, snapshot) {
        final busy =
            store.busy(track.uri) ||
            snapshot.connectionState != ConnectionState.done;
        final saved = snapshot.data == true;
        final VoidCallback? onPressed = busy
            ? null
            : () async {
                if (saved && (canRemove == null || !canRemove!(track.uri))) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.appStrings.offlineInQueue)),
                  );
                  return;
                }
                if (saved && onRemove != null) {
                  onRemove!();
                  return;
                }
                if (!saved) {
                  final confirmed = await showDialog<String>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: Text(context.appStrings.offlineDownload),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.appStrings.offlineNetworkNotice),
                            if (!kIsWeb &&
                                defaultTargetPlatform ==
                                    TargetPlatform.android &&
                                identical(store, AudioLibrary.offline)) ...[
                              const SizedBox(height: 12),
                              Text(context.appStrings.backgroundNotice),
                            ],
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: Text(context.appStrings.uiCancel),
                        ),
                        if (!kIsWeb &&
                            defaultTargetPlatform == TargetPlatform.android &&
                            identical(store, AudioLibrary.offline))
                          TextButton(
                            key: const ValueKey('offline-track-background'),
                            onPressed: () =>
                                Navigator.pop(dialogContext, 'background'),
                            child: Text(context.appStrings.backgroundButton),
                          ),
                        FilledButton(
                          key: const ValueKey('offline-download-confirm'),
                          onPressed: () =>
                              Navigator.pop(dialogContext, 'foreground'),
                          child: Text(context.appStrings.offlineDownload),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == null || !context.mounted) return;
                  if (confirmed == 'background') {
                    await openBackgroundDownloads(context, [track]);
                    onChanged?.call();
                    return;
                  }
                }
                try {
                  if (saved) {
                    await store.remove(track.uri);
                  } else {
                    await store.download(track);
                  }
                  onChanged?.call();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          saved
                              ? context.appStrings.offlineRemoved
                              : context.appStrings.offlineSaved,
                        ),
                      ),
                    );
                  }
                } on DownloadNetworkException {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.appStrings.offlineNetworkBlocked),
                      ),
                    );
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.appStrings.offlineError)),
                    );
                  }
                }
              };
        final label = busy
            ? context.appStrings.offlineWorking
            : saved
            ? context.appStrings.offlineRemove
            : context.appStrings.offlineDownload;
        final icon = saved
            ? Icons.delete_outline_rounded
            : Icons.download_rounded;
        if (iconOnly) {
          return IconButton.filledTonal(
            key: const ValueKey('offline-track-action'),
            tooltip: label,
            icon: Icon(icon),
            onPressed: onPressed,
          );
        }
        return TextButton.icon(
          key: const ValueKey('offline-track-action'),
          icon: Icon(icon),
          label: Text(label),
          onPressed: onPressed,
        );
      },
    ),
  );
}

class OfflineDownloadsScreen extends StatefulWidget {
  const OfflineDownloadsScreen({
    super.key,
    required this.store,
    required this.onPlay,
    required this.canRemove,
    this.playerBar,
  });
  final OfflineStorage store;
  final Future<void> Function(AudioTrack, Uri) onPlay;
  final bool Function(String) canRemove;
  final Widget? playerBar;
  @override
  State<OfflineDownloadsScreen> createState() => _OfflineDownloadsScreenState();
}

class _OfflineDownloadsScreenState extends State<OfflineDownloadsScreen> {
  late Future<List<AudioTrack>> _tracks;
  final Set<String> _pendingRemoval = {};
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _tracks = widget.store.cachedTracks().then(
      (rows) => rows.map(AudioTrack.fromMap).toList(),
    );
  }

  void _removeWithUndo(AudioTrack track, BuildContext itemContext) {
    if (_pendingRemoval.contains(track.uri)) return;
    final messenger = ScaffoldMessenger.of(itemContext);
    final strings = context.appStrings;
    setState(() => _pendingRemoval.add(track.uri));
    final notice = messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(itemContext).colorScheme.onInverseSurface,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${track.displayTitle}: ${strings.offlineRemovePending}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const ValueKey('offline-undo'),
              tooltip: strings.offlineUndo,
              icon: const Icon(Icons.undo_rounded),
              onPressed: () => messenger.hideCurrentSnackBar(
                reason: SnackBarClosedReason.action,
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        persist: false,
      ),
    );
    notice.closed.then((reason) async {
      if (!mounted) return;
      if (reason == SnackBarClosedReason.timeout) {
        try {
          if (!widget.canRemove(track.uri)) {
            messenger.showSnackBar(
              SnackBar(content: Text(strings.offlineInQueue)),
            );
          } else {
            await widget.store.remove(track.uri);
          }
        } catch (_) {
          messenger.showSnackBar(SnackBar(content: Text(strings.offlineError)));
        }
      }
      if (mounted) {
        setState(() {
          _pendingRemoval.remove(track.uri);
          _refresh();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => ScaffoldMessenger(
    child: Scaffold(
      appBar: AppBar(title: Text(context.appStrings.uiOfflineFiles)),
      bottomNavigationBar: widget.playerBar == null
          ? null
          : SafeArea(top: false, child: widget.playerBar!),
      body: FutureBuilder<List<AudioTrack>>(
        future: _tracks,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(context.appStrings.offlineError));
          }
          final tracks = (snapshot.data ?? [])
              .where((track) => !_pendingRemoval.contains(track.uri))
              .toList();
          if (tracks.isEmpty) {
            return Center(child: Text(context.appStrings.offlineEmpty));
          }
          return ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .secondaryContainer,
                    child: Icon(
                      Icons.download_done_rounded,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                  title: Text(
                    track.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    track.displayArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: OfflineTrackAction(
                    store: widget.store,
                    track: track,
                    canRemove: widget.canRemove,
                    onRemove: () => _removeWithUndo(track, context),
                    iconOnly: true,
                    onChanged: () {
                      if (mounted) setState(_refresh);
                    },
                  ),
                  onTap: () async {
                    try {
                      final local = await widget.store.localUri(track.uri);
                      if (local == null) {
                        throw StateError('Offline file unavailable');
                      }
                      await widget.onPlay(track, local);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(context.appStrings.offlineError),
                          ),
                        );
                      }
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

class OfflineSeekBar extends StatelessWidget {
  const OfflineSeekBar({
    super.key,
    required this.positions,
    required this.durations,
    required this.initialPosition,
    required this.fallbackDuration,
    required this.onSeek,
  });

  final Stream<Duration> positions;
  final Stream<Duration?> durations;
  final Duration initialPosition;
  final Duration fallbackDuration;
  final ValueChanged<Duration> onSeek;

  String _format(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: positions,
    initialData: initialPosition,
    builder: (context, positionSnapshot) => StreamBuilder<Duration?>(
      stream: durations,
      initialData: fallbackDuration,
      builder: (context, durationSnapshot) {
        final position = positionSnapshot.data ?? Duration.zero;
        final duration = durationSnapshot.data ?? fallbackDuration;
        final max = duration.inMilliseconds > 0
            ? duration.inMilliseconds.toDouble()
            : 1.0;
        return Row(
          children: [
            const SizedBox(width: 12),
            Text(_format(position)),
            Expanded(
              child: Slider(
                key: const ValueKey('offline-seek-slider'),
                value: position.inMilliseconds.toDouble().clamp(0, max),
                max: max,
                onChanged: duration.inMilliseconds <= 0
                    ? null
                    : (value) => onSeek(Duration(milliseconds: value.round())),
              ),
            ),
            Text(_format(duration)),
            const SizedBox(width: 12),
          ],
        );
      },
    ),
  );
}
