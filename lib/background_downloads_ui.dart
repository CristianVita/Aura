import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_strings.dart';
import 'audio_library.dart';
import 'audio_track.dart';
import 'background_downloads.dart';

final backgroundDownloads = BackgroundDownloads(
  store: AudioLibrary.offline,
  persistence: DeviceDownloadJobPersistence(),
  foreground: AndroidDownloadForeground(),
);

Future<void> openBackgroundDownloads(
  BuildContext context,
  List<AudioTrack> tracks,
) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final strings = context.appStrings;
  if (tracks.map((track) => track.uri).toSet().length > 5000) {
    messenger.showSnackBar(SnackBar(content: Text(strings.backgroundTooMany)));
    return;
  }
  try {
    await backgroundDownloads.load();
    if (backgroundDownloads.storageError ||
        (backgroundDownloads.hasJob && !backgroundDownloads.complete)) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(strings.backgroundExisting)),
        );
        await navigator.push<void>(
          MaterialPageRoute(builder: (_) => const BackgroundDownloadsScreen()),
        );
      }
      return;
    }
    await backgroundDownloads.create(tracks);
    if (context.mounted) {
      await navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const BackgroundDownloadsScreen(autoStart: true),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.backgroundStorageError)),
      );
    }
  }
}

class BackgroundDownloadsScreen extends StatefulWidget {
  const BackgroundDownloadsScreen({
    super.key,
    this.autoStart = false,
    this.job,
  });
  final bool autoStart;
  final BackgroundDownloads? job;
  @override
  State<BackgroundDownloadsScreen> createState() =>
      _BackgroundDownloadsScreenState();
}

class _BackgroundDownloadsScreenState extends State<BackgroundDownloadsScreen> {
  late final BackgroundDownloads job = widget.job ?? backgroundDownloads;
  String? error;
  bool retrying = false;
  @override
  void initState() {
    super.initState();
    job.load();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) resume();
      });
    }
  }

  Future<void> resume() async {
    final s = context.appStrings;
    setState(() => error = null);
    try {
      await job.resume(
        title: s.backgroundTitle,
        progress: s.offlineAlbumProgress,
        stop: s.backgroundStop,
      );
    } on PlatformException catch (e) {
      if (mounted) {
        setState(
          () => error = e.code == 'notification_denied'
              ? s.backgroundPermission
              : s.backgroundStartError,
        );
      }
    } catch (_) {
      if (mounted) setState(() => error = s.backgroundStartError);
    }
  }

  Future<void> discard() async {
    final s = context.appStrings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(s.backgroundDiscard),
        content: Text(s.backgroundDiscardNotice),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(s.uiCancel),
          ),
          FilledButton(
            key: const ValueKey('background-discard-confirm'),
            onPressed: () => Navigator.pop(d, true),
            child: Text(s.backgroundDiscard),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await job.discard();
      if (mounted) setState(() => error = null);
    } catch (_) {
      if (mounted) setState(() => error = s.backgroundStorageError);
    }
  }

  Future<void> retryFailures() async {
    if (retrying) return;
    setState(() {
      retrying = true;
      error = null;
    });
    try {
      await job.retryFailures();
      if (mounted) await resume();
    } catch (_) {
      if (mounted) {
        setState(() => error = context.appStrings.backgroundStorageError);
      }
    } finally {
      if (mounted) setState(() => retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.appStrings;
    return Scaffold(
      appBar: AppBar(title: Text(s.backgroundTitle)),
      body: ListenableBuilder(
        listenable: job,
        builder: (context, _) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(s.backgroundNotice),
                    const SizedBox(height: 20),
                    if (!job.ready || job.saving)
                      const Center(child: CircularProgressIndicator())
                    else if (job.storageError)
                      Text(s.backgroundStorageError)
                    else if (!job.hasJob)
                      Text(s.backgroundEmpty)
                    else ...[
                      Text(
                        job.starting
                            ? s.backgroundStarting
                            : job.running
                            ? (job.stopping
                                  ? s.offlineAlbumStopping
                                  : s.backgroundRunning)
                            : job.complete
                            ? s.backgroundFinished
                            : s.backgroundPaused,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: job.done / job.tracks.length,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${s.offlineAlbumProgress}: ${job.done} / ${job.tracks.length}',
                      ),
                      if (job.failed > 0)
                        Text('${s.offlineAlbumFailed}: ${job.failed}'),
                      if (job.networkBlocked) Text(s.offlineNetworkBlocked),
                      if (job.complete && job.failed > 0)
                        Text(s.backgroundRetryFailures),
                      if (job.complete && job.failed > 0)
                        FilledButton.icon(
                          key: const ValueKey('background-retry-failures'),
                          onPressed: retrying ? null : retryFailures,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(s.uiTryAgain),
                        ),
                      const SizedBox(height: 12),
                      if (job.running)
                        OutlinedButton.icon(
                          key: const ValueKey('background-stop'),
                          onPressed: job.stopping ? null : job.requestStop,
                          icon: const Icon(Icons.pause_rounded),
                          label: Text(s.backgroundPause),
                        )
                      else if (!job.complete)
                        FilledButton.icon(
                          key: const ValueKey('background-resume'),
                          onPressed: job.starting ? null : resume,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(s.backgroundResume),
                        ),
                    ],
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(error!),
                      ),
                    if (job.ready &&
                        !job.saving &&
                        !job.running &&
                        !job.starting &&
                        (job.hasJob || job.storageError))
                      TextButton.icon(
                        key: const ValueKey('background-discard'),
                        onPressed: discard,
                        icon: const Icon(Icons.playlist_remove_rounded),
                        label: Text(s.backgroundDiscard),
                      ),
                    if (job.ready &&
                        !job.saving &&
                        !job.storageError &&
                        job.hasJob) ...[
                      const SizedBox(height: 16),
                      Text(
                        s.backgroundQueueTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (job.ready && !job.saving && !job.storageError && job.hasJob)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList.builder(
                  itemCount: job.tracks.length,
                  itemBuilder: (context, index) {
                    final track = job.tracks[index];
                    final outcome = index < job.done
                        ? job.outcomes[index]
                        : null;
                    final active = index == job.done && job.running;
                    final label = outcome == 1
                        ? s.backgroundItemDone
                        : outcome == 2
                        ? s.backgroundItemFailed
                        : outcome == 0
                        ? s.backgroundItemUnknown
                        : active
                        ? s.backgroundItemDownloading
                        : s.backgroundItemWaiting;
                    final icon = outcome == 1
                        ? Icons.check_circle_outline_rounded
                        : outcome == 2
                        ? Icons.error_outline_rounded
                        : outcome == 0
                        ? Icons.help_outline_rounded
                        : active
                        ? Icons.downloading_rounded
                        : Icons.schedule_rounded;
                    return Card(
                      child: ListTile(
                        key: ValueKey('background-track-$index'),
                        leading: Icon(icon),
                        title: Text(
                          track.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${track.displayArtist} · $label'),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
