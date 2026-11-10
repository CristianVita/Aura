import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_strings.dart';
import 'artwork_memory_cache.dart';

class ArtworkCacheSettings extends StatelessWidget {
  const ArtworkCacheSettings({super.key, required this.cache});
  final ArtworkMemoryCache cache;
  @override
  Widget build(BuildContext context) {
    final s = context.appStrings;
    return Scaffold(
      appBar: AppBar(title: Text(s.uiImages)),
      body: ListenableBuilder(
        listenable: cache,
        builder: (context, _) {
          final format = NumberFormat.decimalPattern(
            Localizations.localeOf(context).toString(),
          );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(s.imageCacheDescription),
              const SizedBox(height: 18),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: Text(s.imageCacheEntries),
                      trailing: Text(format.format(cache.entryCount)),
                    ),
                    ListTile(
                      title: Text(s.imageCacheBytes),
                      trailing: Text('${format.format(cache.byteCount)} B'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.tonalIcon(
                key: const ValueKey('clear-artwork-memory'),
                onPressed: cache.entryCount == 0 ? null : cache.clear,
                icon: const Icon(Icons.cleaning_services_outlined),
                label: Text(s.imageCacheClear),
              ),
              const SizedBox(height: 12),
              Text(s.imageCacheScope),
            ],
          );
        },
      ),
    );
  }
}
