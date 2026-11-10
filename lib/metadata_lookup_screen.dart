import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'app_theme.dart';
import 'audio_track.dart';
import 'metadata_lookup.dart';

class MetadataLookupScreen extends StatefulWidget {
  const MetadataLookupScreen({super.key, required this.track, this.lookup});
  final AudioTrack track;
  final MusicBrainzLookup? lookup;
  @override
  State<MetadataLookupScreen> createState() => _MetadataLookupScreenState();
}

class _MetadataLookupScreenState extends State<MetadataLookupScreen> {
  late final TextEditingController title = TextEditingController(
    text: widget.track.displayTitle,
  );
  late final TextEditingController artist = TextEditingController(
    text: _knownArtist(widget.track.artist),
  );
  bool busy = false, searched = false;
  List<MetadataCandidate> results = const [];
  MetadataLookupFailure? failure;

  static String _knownArtist(String value) {
    final trimmed = value.trim();
    return const {
          '<unknown>',
          '[unknown artist]',
          'unknown artist',
        }.contains(trimmed.toLowerCase())
        ? ''
        : trimmed;
  }

  @override
  void dispose() {
    title.dispose();
    artist.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (busy || title.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      searched = true;
      results = const [];
      failure = null;
    });
    try {
      final found = await (widget.lookup ?? musicBrainzLookup).search(
        title: title.text,
        artist: artist.text,
      );
      if (mounted) setState(() => results = found);
    } on MetadataLookupException catch (error) {
      if (mounted) setState(() => failure = error.reason);
    } catch (_) {
      if (mounted) setState(() => failure = MetadataLookupFailure.unavailable);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.appStrings;
    final error = switch (failure) {
      MetadataLookupFailure.rateLimited => strings.metadataRateLimit,
      MetadataLookupFailure.invalidQuery => strings.metadataInvalidQuery,
      _ => strings.metadataNetworkError,
    };
    return Scaffold(
      appBar: AppBar(title: Text(strings.metadataOnlineTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(strings.metadataPrivacy),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('metadata-title'),
            controller: title,
            maxLength: MusicBrainzLookup.maxQueryLength,
            enabled: !busy,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: strings.uiTitle,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('metadata-artist'),
            controller: artist,
            maxLength: MusicBrainzLookup.maxQueryLength,
            enabled: !busy,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: strings.metadataArtistOptional,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('metadata-search'),
            onPressed: busy || title.text.trim().isEmpty ? null : _search,
            icon: const Icon(Icons.search_rounded),
            label: Text(strings.navigationSearch),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!busy && failure != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(error, key: const ValueKey('metadata-error')),
            ),
          if (!busy && failure == null && searched && results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(strings.metadataNoResults),
            ),
          if (!busy && results.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              strings.metadataPossibleMatches,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              strings.metadataUncertain,
              style: TextStyle(color: context.auraMuted),
            ),
            const SizedBox(height: 12),
            for (final result in results)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (result.artist.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(result.artist),
                      ],
                      if (result.disambiguation.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          result.disambiguation,
                          style: TextStyle(color: context.auraMuted),
                        ),
                      ],
                      if (result.firstReleaseDate.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${strings.metadataFirstRelease}: ${result.firstReleaseDate}',
                        ),
                      ],
                      for (final release in result.releases) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${strings.uiAlbum}: ${release.title}${release.date.isEmpty ? '' : ' · ${release.date}'}',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
