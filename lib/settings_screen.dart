part of 'main.dart';

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen({
    required this.sourceSummary,
    required this.onFilters,
    required this.filtersReady,
    required this.onHistory,
    required this.onManageSources,
    required this.onScan,
    required this.isScanning,
  });
  final String sourceSummary;
  final VoidCallback onFilters, onHistory, onManageSources, onScan;
  final bool filtersReady, isScanning;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
    children: [
      const Text('Aura', style: TextStyle(fontSize: 25)),
      const SizedBox(height: 6),
      const Text('Muzica ta. În ritmul tău.', style: TextStyle(color: _muted)),
      const SizedBox(height: 26),
      _SettingsGroup(
        title: 'Setări',
        children: [
          _SettingsRow(
            icon: Icons.palette_outlined,
            title: 'Interfață',
            subtitle: 'Player și dimensiunea stelelor',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const _InterfaceSettings(),
              ),
            ),
          ),
          _SettingsRow(
            icon: Icons.filter_alt_outlined,
            title: 'Filtre bibliotecă',
            subtitle: 'Durată și foldere de mesagerie',
            onTap: filtersReady ? onFilters : null,
          ),
        ],
      ),
      const SizedBox(height: 24),
      _SettingsGroup(
        title: 'Bibliotecă și surse',
        children: [
          _SettingsRow(
            icon: Icons.dns_outlined,
            title: 'Gestionează sursele',
            subtitle: sourceSummary,
            onTap: isScanning ? null : onManageSources,
          ),
          _SettingsRow(
            icon: Icons.sync_rounded,
            title: isScanning
                ? 'Se actualizează...'
                : 'Actualizează biblioteca',
            onTap: isScanning ? null : onScan,
          ),
          _SettingsRow(
            icon: Icons.history_rounded,
            title: 'Istoric de ascultare',
            onTap: onHistory,
          ),
        ],
      ),
      const SizedBox(height: 24),
      _SettingsGroup(
        title: 'Despre',
        children: [
          _SettingsRow(
            icon: Icons.info_outline_rounded,
            title: 'Despre Aura',
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Aura',
              applicationIcon: Image.asset(
                'assets/branding/aura.png',
                width: 48,
                height: 48,
              ),
              children: [
                const Text(
                  'Player pentru muzica locală și biblioteca ta Navidrome.',
                ),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
        child: Text(title, style: const TextStyle(color: _mint, fontSize: 16)),
      ),
      Material(
        color: const Color(0xFF202C32),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) const Divider(height: 1, color: _background),
              children[index],
            ],
          ],
        ),
      ),
    ],
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
    leading: Icon(icon, size: 23),
    title: Text(title),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: const TextStyle(color: _muted, fontSize: 12)),
    trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: _muted),
    onTap: onTap,
  );
}

class _InterfaceSettings extends StatelessWidget {
  const _InterfaceSettings();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Interfață'),
      backgroundColor: _background,
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SettingsGroup(
          title: 'Ecran de redare',
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: RatingSizeSettings(),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            'Glisează pe stele pentru rating în pași de jumătate de stea. Preferința de dimensiune se aplică în player și în informațiile piesei.',
            style: TextStyle(color: _muted, height: 1.5),
          ),
        ),
      ],
    ),
  );
}
