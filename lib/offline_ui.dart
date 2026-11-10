import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'audio_track.dart';
import 'offline_storage.dart';
import 'download_network_policy.dart';

class OfflineTrackAction extends StatelessWidget {
  const OfflineTrackAction({
    super.key,
    required this.store,
    required this.track,
    this.onChanged,
    this.canRemove,
  });
  final OfflineStorage store;
  final AudioTrack track;
  final VoidCallback? onChanged;
  final bool Function(String)? canRemove;
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
        return TextButton.icon(
          key: const ValueKey('offline-track-action'),
          icon: Icon(saved ? Icons.download_done : Icons.download_outlined),
          label: Text(
            busy
                ? context.appStrings.offlineWorking
                : saved
                ? context.appStrings.offlineRemove
                : context.appStrings.offlineDownload,
          ),
          onPressed: busy
              ? null
              : () async {
                  if (saved && (canRemove == null || !canRemove!(track.uri))) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.appStrings.offlineInQueue),
                      ),
                    );
                    return;
                  }
                  if (!saved) {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(context.appStrings.offlineDownload),
                        content: Text(context.appStrings.offlineNetworkNotice),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: Text(context.appStrings.uiCancel),
                          ),
                          FilledButton(
                            key: const ValueKey('offline-download-confirm'),
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: Text(context.appStrings.offlineDownload),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !context.mounted) return;
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
                          content: Text(
                            context.appStrings.offlineNetworkBlocked,
                          ),
                        ),
                      );
                    }
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

  @override
  Widget build(BuildContext context) => Scaffold(
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
        final tracks = snapshot.data ?? [];
        if (tracks.isEmpty) {
          return Center(child: Text(context.appStrings.offlineEmpty));
        }
        return ListView.builder(
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final track = tracks[index];
            return Card(
              child: Column(
                children: [
                  ListTile(
                    title: Text(track.displayTitle),
                    subtitle: Text(track.displayArtist),
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
                  Align(
                    alignment: Alignment.centerRight,
                    child: OfflineTrackAction(
                      store: widget.store,
                      track: track,
                      canRemove: widget.canRemove,
                      onChanged: () {
                        if (mounted) setState(_refresh);
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
