import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'album_artwork.dart';
import 'app_strings.dart';
import 'cover_lookup.dart';

class CoverLookupScreen extends StatefulWidget {
  const CoverLookupScreen({
    super.key,
    required this.albumKey,
    required this.initialTitle,
    this.lookup,
    this.save,
  });
  final String albumKey, initialTitle;
  final CoverLookup? lookup;
  final Future<void> Function(String, Uint8List)? save;
  @override
  State<CoverLookupScreen> createState() => _CoverLookupScreenState();
}

class _CoverLookupScreenState extends State<CoverLookupScreen> {
  late final title = TextEditingController(text: widget.initialTitle);
  final artist = TextEditingController();
  bool busy = false, searched = false, failed = false, previewing = false;
  List<CoverCandidate> results = [];
  CoverLookup get lookup => widget.lookup ?? coverLookup;

  @override
  void dispose() {
    title.dispose();
    artist.dispose();
    super.dispose();
  }

  Future<void> search() async {
    if (busy || title.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      searched = true;
      failed = false;
      results = [];
    });
    try {
      final found = await lookup.search(title.text, artist.text);
      if (mounted) setState(() => results = found);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> choose(CoverCandidate candidate) async {
    if (busy) return;
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      final bytes = await lookup.front(candidate.id);
      if (!mounted) return;
      final strings = context.appStrings;
      setState(() => previewing = true);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(strings.coverOnlinePreview),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.memory(
                  bytes,
                  height: 240,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Text(strings.albumCoverError),
                ),
                const SizedBox(height: 12),
                Text(candidate.title),
                if (candidate.artist.isNotEmpty) Text(candidate.artist),
                const SizedBox(height: 12),
                Text(strings.coverOnlineSaveNotice),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(strings.uiCancel),
            ),
            FilledButton(
              key: const ValueKey('cover-online-confirm'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(strings.coverOnlineUse),
            ),
          ],
        ),
      );
      if (mounted) setState(() => previewing = false);
      if (confirmed == true && mounted) {
        await (widget.save ?? albumArtwork.set)(widget.albumKey, bytes);
        if (mounted) Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          previewing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.appStrings;
    return Scaffold(
      appBar: AppBar(title: Text(s.coverOnlineTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(s.coverOnlinePrivacy),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('cover-online-title'),
            controller: title,
            enabled: !busy,
            maxLength: 200,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: s.uiAlbum,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('cover-online-artist'),
            controller: artist,
            enabled: !busy,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: s.metadataArtistOptional,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('cover-online-search'),
            onPressed: busy || title.text.trim().isEmpty ? null : search,
            icon: const Icon(Icons.search),
            label: Text(s.navigationSearch),
          ),
          if (busy && !previewing)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!busy && failed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(s.coverOnlineError),
            ),
          if (!busy && searched && !failed && results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(s.metadataNoResults),
            ),
          if (results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(s.coverOnlineSelect),
            ),
          for (final candidate in results)
            Card(
              child: ListTile(
                enabled: !busy,
                title: Text(candidate.title),
                subtitle: Text(
                  [
                    candidate.artist,
                    candidate.date,
                  ].where((v) => v.isNotEmpty).join(' · '),
                ),
                trailing: const Icon(Icons.image_search_outlined),
                onTap: () => choose(candidate),
              ),
            ),
        ],
      ),
    );
  }
}
