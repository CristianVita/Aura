import 'audio_track.dart';
import 'library_preferences.dart';

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
