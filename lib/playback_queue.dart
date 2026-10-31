import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_track.dart';
import 'track_artwork.dart';

const _mint = Color(0xFF8BE0C0);

class PlaybackOptions extends StatefulWidget {
  const PlaybackOptions({super.key, required this.player});
  final AudioPlayer player;

  @override
  State<PlaybackOptions> createState() => _PlaybackOptionsState();
}

class _PlaybackOptionsState extends State<PlaybackOptions> {
  bool _busy = false;

  Future<void> _change(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) _showError(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return StreamBuilder<SequenceState>(
      stream: player.sequenceStateStream,
      initialData: player.sequenceState,
      builder: (context, snapshot) {
        final state = snapshot.data!;
        final repeatLabel = switch (state.loopMode) {
          LoopMode.off => 'Repeat oprit',
          LoopMode.all => 'Repetă toată coada',
          LoopMode.one => 'Repetă piesa curentă',
        };
        return Row(
          children: [
            IconButton(
              tooltip: state.shuffleModeEnabled
                  ? 'Shuffle activ'
                  : 'Shuffle oprit',
              isSelected: state.shuffleModeEnabled,
              selectedIcon: const Icon(Icons.shuffle_rounded, color: _mint),
              icon: const Icon(Icons.shuffle_rounded),
              onPressed: _busy
                  ? null
                  : () => _change(() async {
                      final enabled = !player.shuffleModeEnabled;
                      if (enabled) await player.shuffle();
                      await player.setShuffleModeEnabled(enabled);
                    }),
            ),
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.queue_music_rounded),
                label: Text('Coada · ${state.sequence.length}'),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: const Color(0xFF141D22),
                  builder: (_) => PlaybackQueueSheet(player: player),
                ),
              ),
            ),
            IconButton(
              tooltip: repeatLabel,
              icon: Icon(
                state.loopMode == LoopMode.one
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                color: state.loopMode == LoopMode.off ? null : _mint,
              ),
              onPressed: _busy
                  ? null
                  : () => _change(
                      () => player.setLoopMode(switch (player.loopMode) {
                        LoopMode.off => LoopMode.all,
                        LoopMode.all => LoopMode.one,
                        LoopMode.one => LoopMode.off,
                      }),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class PlaybackQueueSheet extends StatefulWidget {
  const PlaybackQueueSheet({super.key, required this.player});
  final AudioPlayer player;

  @override
  State<PlaybackQueueSheet> createState() => _PlaybackQueueSheetState();
}

class _PlaybackQueueSheetState extends State<PlaybackQueueSheet> {
  bool _busy = false;

  Future<void> _preserveCurrent(Future<void> Function() change) async {
    final player = widget.player;
    final current = player.sequenceState.currentSource;
    final position = player.position;
    // An ended playlist can still have playing=true. Keep an edit from
    // advancing it when the native timeline becomes playable again.
    if (player.processingState == ProcessingState.completed) {
      await player.pause();
    }
    await change();
    final index = current == null ? -1 : player.sequence.indexOf(current);
    if (index >= 0 && !identical(player.sequenceState.currentSource, current)) {
      await player.seek(position, index: index);
    }
  }

  Future<void> _edit(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) _showError(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: StreamBuilder<SequenceState>(
          stream: player.sequenceStateStream,
          initialData: player.sequenceState,
          builder: (context, snapshot) {
            final state = snapshot.data!;
            // Use source identity, including duplicate tracks, for row keys and
            // resolve indices again after async player updates.
            final sources = state.effectiveSequence;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Coada de redare · ${sources.length}',
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Închide coada',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Text(
                    state.shuffleModeEnabled
                        ? 'Ordine amestecată. Oprește shuffle pentru a reordona.'
                        : 'Trage de mâner pentru a schimba ordinea.',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: sources.isEmpty
                      ? const Center(child: Text('Coada este goală'))
                      : ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          padding: const EdgeInsets.only(bottom: 20),
                          itemCount: sources.length,
                          onReorderItem: (oldIndex, newIndex) {
                            if (_busy || player.shuffleModeEnabled) return;
                            // A track can advance while the user is dragging.
                            final source = sources[oldIndex];
                            final actual = player.sequence.indexOf(source);
                            if (actual < 0) return;
                            _edit(
                              () => _preserveCurrent(
                                () => player.moveAudioSource(actual, newIndex),
                              ),
                            );
                          },
                          itemBuilder: (context, index) {
                            final source = sources[index];
                            final track = audioTrackOf(source)!;
                            final current = identical(
                              source,
                              state.currentSource,
                            );
                            return ListTile(
                              key: ObjectKey(source),
                              selected: current,
                              selectedTileColor: _mint.withValues(alpha: .08),
                              contentPadding: const EdgeInsets.only(
                                left: 16,
                                right: 4,
                              ),
                              leading: TrackArtwork(
                                uri: track.artworkUri.toString(),
                                cacheKey: track.artworkKey,
                                size: 42,
                              ),
                              title: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                current
                                    ? 'Piesa curentă · ${track.artist}'
                                    : track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: _busy
                                  ? null
                                  : () => _edit(() async {
                                      final actual = player.sequence.indexOf(
                                        source,
                                      );
                                      if (actual < 0) return;
                                      await player.seek(
                                        Duration.zero,
                                        index: actual,
                                      );
                                      unawaited(
                                        player.play().catchError((
                                          Object error,
                                        ) {
                                          if (context.mounted) {
                                            _showError(context);
                                          }
                                        }),
                                      );
                                    }),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Elimină ${track.title} din coadă',
                                    icon: const Icon(
                                      Icons.remove_circle_outline_rounded,
                                      size: 21,
                                    ),
                                    onPressed: _busy
                                        ? null
                                        : () => _edit(() async {
                                            final actual = player.sequence
                                                .indexOf(source);
                                            if (actual < 0) return;
                                            if (player.sequence.length == 1) {
                                              await player.stop();
                                              await player.clearAudioSources();
                                            } else {
                                              await _preserveCurrent(
                                                () =>
                                                    player.removeAudioSourceAt(
                                                      actual,
                                                    ),
                                              );
                                            }
                                          }),
                                  ),
                                  if (!state.shuffleModeEnabled && !_busy)
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: Semantics(
                                        label: 'Mută ${track.title}',
                                        child: const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: Icon(
                                            Icons.drag_handle_rounded,
                                            color: Colors.white54,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    const SizedBox(width: 48),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

void _showError(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Nu am putut actualiza redarea. Încearcă din nou.'),
    ),
  );
}
