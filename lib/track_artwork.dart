import 'audio_library.dart';
import 'album_artwork.dart';
import 'artwork_memory_cache.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final artworkMemoryCache = ArtworkMemoryCache(
  read: (uri) async {
    try {
      return await const AudioLibrary().invokeMethod<Uint8List>('loadArtwork', {
        'uri': uri,
      });
    } catch (_) {
      return null;
    }
  },
);

class TrackArtwork extends StatefulWidget {
  const TrackArtwork({
    super.key,
    required this.uri,
    required this.cacheKey,
    required this.size,
    this.radius = 13,
    this.fallbackIcon = Icons.music_note_rounded,
    this.album = '',
    this.albumStore,
  });
  final String uri;
  final String cacheKey;
  final double size;
  final double radius;
  final IconData fallbackIcon;
  final String album;
  final AlbumArtworkStore? albumStore;

  @override
  State<TrackArtwork> createState() => _TrackArtworkState();
}

class _TrackArtworkState extends State<TrackArtwork> {
  late Future<Uint8List?> _artwork;
  AlbumArtworkStore get _store => widget.albumStore ?? albumArtwork;
  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
    _artwork = _load();
  }

  Future<Uint8List?> _load() async =>
      await _store.read(widget.album) ??
      await artworkMemoryCache.load(widget.uri, widget.cacheKey);

  void _changed() {
    if (mounted) {
      setState(() {
        _artwork = _load();
      });
    }
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    super.dispose();
  }

  @override
  void didUpdateWidget(TrackArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.albumStore != widget.albumStore) {
      (oldWidget.albumStore ?? albumArtwork).removeListener(_changed);
      _store.addListener(_changed);
    }
    if (oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.uri != widget.uri ||
        oldWidget.album != widget.album ||
        oldWidget.albumStore != widget.albumStore) {
      _artwork = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final fallback = ColoredBox(
      color: color.withValues(alpha: 0.1),
      child: Center(
        child: Icon(
          widget.fallbackIcon,
          color: color,
          size: widget.size * 0.48,
        ),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: FutureBuilder<Uint8List?>(
            key: ValueKey(widget.cacheKey),
            future: _artwork,
            builder: (context, snapshot) {
              final bytes = snapshot.connectionState == ConnectionState.done
                  ? snapshot.data
                  : null;
              if (bytes == null || bytes.isEmpty) return fallback;
              return Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: false,
                errorBuilder: (context, error, stackTrace) => fallback,
              );
            },
          ),
        ),
      ),
    );
  }
}
