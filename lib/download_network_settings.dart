import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'download_network_policy.dart';

class DownloadNetworkSettings extends StatefulWidget {
  const DownloadNetworkSettings({super.key, required this.policy});
  final DownloadNetworkPolicy policy;
  @override
  State<DownloadNetworkSettings> createState() =>
      _DownloadNetworkSettingsState();
}

class _DownloadNetworkSettingsState extends State<DownloadNetworkSettings> {
  bool saving = false;
  @override
  void initState() {
    super.initState();
    widget.policy.load();
  }

  Future<void> select(DownloadNetworkMode mode) async {
    setState(() => saving = true);
    try {
      await widget.policy.setMode(mode);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.appStrings.offlineNetworkSaveError)),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.appStrings.uiGeneral)),
    body: ListenableBuilder(
      listenable: widget.policy,
      builder: (context, _) {
        final s = context.appStrings;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              s.offlineNetworkTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final mode in DownloadNetworkMode.values)
              Card(
                child: ListTile(
                  key: ValueKey('network-${mode.name}'),
                  title: Text(
                    mode == DownloadNetworkMode.wifiOnly
                        ? s.offlineNetworkWifi
                        : s.offlineNetworkAny,
                  ),
                  trailing: widget.policy.ready && widget.policy.mode == mode
                      ? const Icon(Icons.check_circle)
                      : const Icon(Icons.circle_outlined),
                  enabled: widget.policy.ready && !saving,
                  onTap: () => select(mode),
                ),
              ),
            const SizedBox(height: 16),
            Text(s.offlineNetworkExplanation),
          ],
        );
      },
    ),
  );
}
