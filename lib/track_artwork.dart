import 'audio_library.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shares in-flight requests and keeps a bounded cache of small cover images.
class _ArtworkCache {
  static const _channel = AudioLibrary();
  static final _requests = <String, Future<Uint8List?>>{};

  static Future<Uint8List?> load(String uri, String key) {
    final existing = _requests.remove(key);
    if (existing != null) {
      _requests[key] = existing;
      return existing;
    }
    final request = _read(uri);
    _requests[key] = request;
    while (_requests.length > 64) {
      _requests.remove(_requests.keys.first);
    }
    return request;
  }

  static Future<Uint8List?> _read(String uri) async {
    try {
      return await _channel.invokeMethod<Uint8List>('loadArtwork', {
        'uri': uri,
      });
    } catch (_) {
      return null;
    }
  }
}

class TrackArtwork extends StatefulWidget {
  const TrackArtwork({
    super.key,
    required this.uri,
    required this.cacheKey,
    required this.size,
    this.radius = 13,
    this.fallbackIcon = Icons.music_note_rounded,
  });
  final String uri;
  final String cacheKey;
  final double size;
  final double radius;
  final IconData fallbackIcon;

  @override
  State<TrackArtwork> createState() => _TrackArtworkState();
}

class _TrackArtworkState extends State<TrackArtwork> {
  late Future<Uint8List?> _artwork;
  @override
  void initState() {
    super.initState();
    _artwork = _ArtworkCache.load(widget.uri, widget.cacheKey);
  }

  @override
  void didUpdateWidget(TrackArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey || oldWidget.uri != widget.uri) {
      _artwork = _ArtworkCache.load(widget.uri, widget.cacheKey);
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
