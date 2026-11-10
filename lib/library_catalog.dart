import 'audio_track.dart';
import 'library_preferences.dart';

/// Returns a new browse order. Missing values sort last; ties keep input order.
List<AudioTrack> sortLibraryTracks(
  Iterable<AudioTrack> tracks,
  TrackSort sort, {
  int Function(AudioTrack, AudioTrack)? primary,
}) {
  final indexed = tracks.indexed.toList();
  if (sort == TrackSort.original) {
    return indexed.map((entry) => entry.$2).toList();
  }
  String text(AudioTrack track) => switch (sort) {
    TrackSort.title => track.displayTitle,
    TrackSort.artist => track.artist,
    TrackSort.album => track.album,
    TrackSort.genre => track.genre,
    _ => '',
  };
  int number(AudioTrack track) => switch (sort) {
    TrackSort.year => metadataYear(track.year),
    TrackSort.duration => track.durationMs > 0 ? track.durationMs : 0,
    _ => 0,
  };
  indexed.sort((a, b) {
    final priority = primary?.call(a.$2, b.$2) ?? 0;
    if (priority != 0) return priority;
    int comparison;
    if (sort == TrackSort.year || sort == TrackSort.duration) {
      final left = number(a.$2), right = number(b.$2);
      comparison = left == 0 && right != 0
          ? 1
          : right == 0 && left != 0
          ? -1
          : left.compareTo(right);
    } else {
      final left = text(a.$2).trim().toLowerCase(),
          right = text(b.$2).trim().toLowerCase();
      comparison = left.isEmpty && right.isNotEmpty
          ? 1
          : right.isEmpty && left.isNotEmpty
          ? -1
          : left.compareTo(right);
    }
    return comparison != 0 ? comparison : a.$1.compareTo(b.$1);
  });
  return indexed.map((entry) => entry.$2).toList();
}

List<MapEntry<String, List<AudioTrack>>> orderedLibraryGroups(
  Map<String, List<AudioTrack>> groups,
  GroupSort sort,
) {
  final entries = groups.entries.toList();
  entries.sort((a, b) {
    final count = sort == GroupSort.trackCount
        ? b.value.length.compareTo(a.value.length)
        : 0;
    if (count != 0) return count;
    final folded = a.key.toLowerCase().compareTo(b.key.toLowerCase());
    final name = folded == 0 ? a.key.compareTo(b.key) : folded;
    return sort == GroupSort.nameDescending ? -name : name;
  });
  return entries;
}

int libraryGridColumns(double width, int preferred, double textScale) {
  final responsive = width >= 650
      ? (width / 160).floor().clamp(preferred, 8)
      : preferred;
  final readable = (width / (80 * textScale.clamp(1.0, 2.0))).floor().clamp(
    1,
    8,
  );
  return responsive.clamp(1, readable);
}
