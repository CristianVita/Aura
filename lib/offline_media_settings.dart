import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_strings.dart';
import 'offline_storage.dart';
import 'playback_cache.dart';

class OfflineMediaSettings extends StatefulWidget {
  const OfflineMediaSettings({
    super.key,
    required this.store,
    required this.onOpenDownloads,
    this.cache,
  });
  final OfflineStorage store;
  final VoidCallback? onOpenDownloads;
  final PlaybackCache? cache;
  @override
  State<OfflineMediaSettings> createState() => _OfflineMediaSettingsState();
}

class _OfflineMediaSettingsState extends State<OfflineMediaSettings> {
  late Future<OfflineMediaUsage> usage;
  bool clearing = false;
  @override
  void initState() {
    super.initState();
    usage = widget.store.mediaUsage();
    widget.store.addListener(refresh);
    widget.cache?.addListener(refresh);
    widget.cache?.load();
  }

  void refresh() {
    if (mounted) {
      setState(() {
        usage = widget.store.mediaUsage();
      });
    }
  }

  @override
  void didUpdateWidget(covariant OfflineMediaSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cache != widget.cache) {
      oldWidget.cache?.removeListener(refresh);
      widget.cache?.addListener(refresh);
      widget.cache?.load();
    }
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(refresh);
      widget.store.addListener(refresh);
      usage = widget.store.mediaUsage();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(refresh);
    widget.cache?.removeListener(refresh);
    super.dispose();
  }

  Future<void> clearCache(PlaybackCache cache) async {
    final s = context.appStrings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.playbackCacheClear),
        content: Text(s.playbackCacheClearNotice),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(s.uiCancel),
          ),
          FilledButton(
            key: const ValueKey('playback-cache-clear-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(s.playbackCacheClear),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => clearing = true);
    try {
      final skipped = await cache.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              skipped > 0
                  ? s.playbackCacheClearPartial
                  : s.playbackCacheCleared,
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.offlineError)));
      }
    } finally {
      if (mounted) setState(() => clearing = false);
    }
  }

  String formatBytes(int bytes, Locale locale) {
    const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${NumberFormat.decimalPatternDigits(locale: locale.toString(), decimalDigits: unit == 0 ? 0 : 2).format(value)} ${units[unit]}';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.appStrings;
    return Scaffold(
      appBar: AppBar(title: Text(s.uiMedia)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.cache case final cache?) ...[
            SwitchListTile(
              key: const ValueKey('playback-cache-enabled'),
              title: Text(s.playbackCacheTitle),
              subtitle: Text(s.playbackCacheDescription),
              value: cache.enabled,
              onChanged: !cache.ready || !cache.available || clearing
                  ? null
                  : (value) async {
                      try {
                        await cache.setEnabled(value);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(s.offlineNetworkSaveError)),
                          );
                        }
                      }
                    },
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('playback-cache-clear'),
                onPressed: !cache.ready || !cache.available || clearing
                    ? null
                    : () => clearCache(cache),
                icon: const Icon(Icons.delete_outline),
                label: Text(s.playbackCacheClear),
              ),
            ),
            if (cache.ready && !cache.available)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(s.playbackCacheUnavailable),
              ),
            const SizedBox(height: 18),
          ],
          Text(s.offlineMediaDescription),
          const SizedBox(height: 18),
          FutureBuilder<OfflineMediaUsage>(
            future: usage,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return Text(s.offlineError);
              }
              final data = snapshot.data!;
              return Card(
                child: Column(
                  children: [
                    ListTile(
                      title: Text(s.offlineMediaTracks),
                      trailing: Text(
                        NumberFormat.decimalPattern(
                          Localizations.localeOf(context).toString(),
                        ).format(data.tracks),
                      ),
                    ),
                    ListTile(
                      title: Text(s.offlineMediaSize),
                      trailing: Text(
                        formatBytes(
                          data.bytes,
                          Localizations.localeOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey('offline-media-manage'),
            onPressed: widget.onOpenDownloads,
            icon: const Icon(Icons.download_done),
            label: Text(s.offlineMediaManage),
          ),
        ],
      ),
    );
  }
}
