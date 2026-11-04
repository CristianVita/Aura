part of 'main.dart';

void _settingsHelp(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Setările Aura'),
    content: const Text(
      'Opțiunile marcate „În pregătire” nu sunt încă disponibile. Setările active se salvează pe acest dispozitiv. Conexiunile la servere se gestionează din Surse media.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Am înțeles'),
      ),
    ],
  ),
);

Future<void> _settingsPage(
  BuildContext context,
  String title,
  List<Widget> Function(BuildContext) buildChildren,
) => Navigator.push<void>(
  context,
  MaterialPageRoute(
    builder: (context) => Scaffold(
      backgroundColor: context.auraBackground,
      appBar: AppBar(
        backgroundColor: context.auraBackground,
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Ajutor',
            onPressed: () => _settingsHelp(context),
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        children: buildChildren(context),
      ),
    ),
  ),
);

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.sourceSummary,
    required this.controls,
    required this.onFilters,
    required this.filtersReady,
    required this.onHistory,
    this.onBackup,
    required this.onManageSources,
    required this.onScan,
    required this.isScanning,
  });
  final String sourceSummary;
  final PlaybackSettingsController controls;
  final VoidCallback onFilters, onHistory, onManageSources, onScan;
  final VoidCallback? onBackup;
  final bool filtersReady, isScanning;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Aura',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w400),
            ),
          ),
          IconButton(
            tooltip: 'Ajutor',
            onPressed: () => _settingsHelp(context),
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      const SizedBox(height: 20),
      _SettingsGroup(
        title: 'Setări',
        children: [
          _SettingsRow(
            icon: Icons.touch_app_outlined,
            title: 'Interfață',
            onTap: () => _settingsPage(
              context,
              'Setări de interfață',
              (context) => [
                _SettingsGroup(
                  title: 'Stilul aplicației',
                  collapsible: true,
                  children: [
                    _SettingsRow(
                      icon: Icons.palette_outlined,
                      title: context.appStrings.appearanceTitle,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AppearanceSettingsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SettingsGroup(
                  title: 'General',
                  collapsible: true,
                  children: [
                    _SettingsRow(
                      icon: Icons.folder_outlined,
                      title: context.appStrings.navigationTitle,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NavigationSettingsScreen(),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.view_list_outlined,
                      title: 'Liste media',
                      onTap: filtersReady ? onFilters : null,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SettingsGroup(
                  title: 'Ecrane de redare',
                  collapsible: true,
                  children: [
                    _SettingsRow(
                      icon: Icons.play_circle_outline,
                      title: 'Ecran de redare',
                      onTap: () => _settingsPage(
                        context,
                        'Ecran de redare',
                        (context) => [
                          const _SettingsGroup(
                            title: 'Ratingul pieselor',
                            children: [
                              Padding(
                                padding: EdgeInsets.all(8),
                                child: RatingSizeSettings(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Glisează pe stele pentru rating în pași de jumătate de stea. Dimensiunea se aplică în player și în informațiile piesei.',
                            style: TextStyle(
                              color: context.auraMuted,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SettingsGroup(
                  title: 'Setări pagini',
                  collapsible: true,
                  children: [
                    _SettingsRow(
                      icon: Icons.home_outlined,
                      title: 'Pagina Acasă',
                      onTap: null,
                      pending: true,
                    ),
                    _SettingsRow(
                      icon: Icons.library_music_outlined,
                      title: 'Pagina Bibliotecă',
                      onTap: null,
                      pending: true,
                    ),
                    _SettingsRow(
                      icon: Icons.album_outlined,
                      title: 'Pagina Album',
                      onTap: null,
                      pending: true,
                    ),
                    _SettingsRow(
                      icon: Icons.person_outline,
                      title: 'Pagina Artist',
                      onTap: null,
                      pending: true,
                    ),
                    _SettingsRow(
                      icon: Icons.style_outlined,
                      title: 'Pagina Gen muzical',
                      onTap: null,
                      pending: true,
                    ),
                    _SettingsRow(
                      icon: Icons.queue_music,
                      title: 'Pagina Playlist',
                      onTap: null,
                      pending: true,
                    ),
                    _SettingsRow(
                      icon: Icons.search,
                      title: 'Pagina Căutare',
                      onTap: null,
                      pending: true,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SettingsGroup(
                  title: 'Avansat',
                  collapsible: true,
                  children: [
                    _SettingsRow(
                      icon: Icons.settings_outlined,
                      title: 'Setări avansate de interfață',
                      onTap: null,
                      pending: true,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          _SettingsRow(
            icon: Icons.radio_outlined,
            title: 'Redare',
            onTap: () => _settingsPage(
              context,
              'Setări de redare',
              (context) => [
                _SettingsGroup(
                  title: '',
                  children: [
                    _SettingsRow(
                      icon: Icons.headphones_outlined,
                      title: 'Setări de ieșire',
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlaybackSettingsScreen(
                            controls: controls,
                            section: PlaybackSettingsSection.output,
                          ),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.graphic_eq,
                      title: 'Redare',
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlaybackSettingsScreen(
                            controls: controls,
                            section: PlaybackSettingsSection.playback,
                          ),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.auto_awesome_outlined,
                      title: 'Acțiuni automate',
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlaybackSettingsScreen(
                            controls: controls,
                            section: PlaybackSettingsSection.timer,
                          ),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.tune,
                      title: 'Decodare și transcodare',
                      onTap: null,
                      pending: true,
                    ),
                    _SettingsRow(
                      icon: Icons.compare_arrows,
                      title: 'Tranziții',
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const _AudioFeatureSettings(
                            page: _AudioFeaturePage.transitions,
                          ),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.info_outline,
                      title: 'Focalizare audio',
                      onTap: null,
                      pending: true,
                    ),
                    _SettingsRow(
                      icon: Icons.headphones_outlined,
                      title: 'Butoanele căștilor',
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const _AudioFeatureSettings(
                            page: _AudioFeaturePage.headset,
                          ),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.view_sidebar_outlined,
                      title: 'Butoane notificare și sesiune media',
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const _AudioFeatureSettings(
                            page: _AudioFeaturePage.notification,
                          ),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.settings_outlined,
                      title: 'Setări avansate de redare',
                      onTap: null,
                      pending: true,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          _SettingsRow(
            icon: Icons.download_outlined,
            title: 'Offline, cache și descărcări',
            onTap: () => _settingsPage(
              context,
              'Offline, cache și descărcări',
              (context) => [
                _SettingsGroup(
                  title: '',
                  children: [
                    _SettingsRow(
                      icon: Icons.download_outlined,
                      title: 'General',
                      onTap: null,
                      pending: true,
                    ),
                    _SettingsRow(
                      icon: Icons.music_note_outlined,
                      title: 'Media',
                      onTap: null,
                      pending: true,
                    ),
                    _SettingsRow(
                      icon: Icons.play_arrow_outlined,
                      title: 'Redare offline de pe server',
                      onTap: null,
                      pending: true,
                    ),
                    _SettingsRow(
                      icon: Icons.image_outlined,
                      title: 'Imagini',
                      onTap: null,
                      pending: true,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Piesele locale funcționează fără internet. Descărcarea pieselor de pe server și administrarea cache-ului sunt în pregătire.',
                  style: TextStyle(color: context.auraMuted, height: 1.5),
                ),
              ],
            ),
          ),
          _SettingsRow(
            icon: Icons.directions_car_outlined,
            title: 'Android Auto',
            onTap: null,
            pending: true,
          ),
          _SettingsRow(
            icon: Icons.memory_outlined,
            title: 'Avansat',
            onTap: () => _settingsPage(
              context,
              'Setări avansate',
              (context) => [
                _SettingsGroup(
                  title: 'Bibliotecă',
                  children: [
                    _SettingsRow(
                      icon: Icons.filter_alt_outlined,
                      title: 'Filtre bibliotecă',
                      onTap: filtersReady ? onFilters : null,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      _SettingsGroup(
        title: 'Diverse',
        children: [
          _SettingsRow(
            icon: Icons.devices_outlined,
            title: 'Surse media',
            onTap: isScanning ? null : onManageSources,
          ),
          _SettingsRow(
            icon: Icons.sync,
            title: 'Manager de sincronizare',
            onTap: () => _settingsPage(
              context,
              'Manager de sincronizare',
              (context) => [
                _SettingsGroup(
                  title: 'Bibliotecă',
                  children: [
                    _SettingsRow(
                      icon: Icons.sync,
                      title: isScanning
                          ? 'Se actualizează…'
                          : 'Actualizează biblioteca',
                      subtitle: sourceSummary,
                      onTap: isScanning ? null : onScan,
                    ),
                    _SettingsRow(
                      icon: Icons.dns_outlined,
                      title: 'Actualizează sursele Navidrome',
                      onTap: isScanning ? null : onManageSources,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          _SettingsRow(
            icon: Icons.download_done_outlined,
            title: 'Fișiere offline',
            onTap: null,
            pending: true,
          ),
          _SettingsRow(
            icon: Icons.folder_copy_outlined,
            title: 'Fișiere generate',
            onTap: null,
            pending: true,
          ),
          _SettingsRow(
            icon: Icons.settings_backup_restore,
            title: 'Backup și restaurare',
            onTap: onBackup,
            pending: onBackup == null,
          ),
          _SettingsRow(
            icon: Icons.history,
            title: 'Istoric de ascultare',
            onTap: onHistory,
          ),
          _SettingsRow(
            icon: Icons.translate,
            title: 'Traduceri',
            onTap: null,
            pending: true,
          ),
        ],
      ),
      const SizedBox(height: 24),
      _SettingsGroup(
        title: 'Despre',
        children: [
          _SettingsRow(
            icon: Icons.star_border,
            title: 'Evaluează aplicația',
            onTap: null,
            pending: true,
          ),
          _SettingsRow(
            icon: Icons.help_outline,
            title: 'Ajutor',
            onTap: () => _settingsHelp(context),
          ),
          _SettingsRow(
            icon: Icons.support_agent,
            title: 'Contactează suportul',
            onTap: null,
            pending: true,
          ),
          _SettingsRow(
            icon: Icons.description_outlined,
            title: 'Noutăți',
            onTap: () => _settingsPage(
              context,
              'Noutăți Aura',
              (context) => [
                const Text(
                  'Bibliotecă locală și Navidrome • Ratinguri în jumătăți de stea • Istoric, playlisturi și favorite • Crossfade, temporizator și egalizator Android • Ecrane de până la 144 Hz',
                  style: TextStyle(height: 1.8),
                ),
              ],
            ),
          ),
          _SettingsRow(
            icon: Icons.info_outline,
            title: 'Despre Aura',
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Aura',
              applicationIcon: Image.asset(
                'assets/branding/aura.png',
                width: 48,
                height: 48,
              ),
              children: const [
                Text('Player pentru muzica locală și biblioteca ta Navidrome.'),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
    ],
  );
}

class _SettingsGroup extends StatefulWidget {
  const _SettingsGroup({
    required this.title,
    required this.children,
    this.collapsible = false,
  });
  final String title;
  final List<Widget> children;
  final bool collapsible;
  @override
  State<_SettingsGroup> createState() => _SettingsGroupState();
}

class _SettingsGroupState extends State<_SettingsGroup> {
  bool _expanded = true;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.title.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 4, 10),
          child: widget.collapsible
              ? InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            style: TextStyle(
                              color: context.auraAccent,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          color: context.auraAccent,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                )
              : Text(
                  widget.title,
                  style: TextStyle(
                    color: context.auraAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                  ),
                ),
        ),
      if (_expanded || !widget.collapsible)
        Material(
          color: context.auraSettingsSurface,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < widget.children.length; index++) ...[
                if (index > 0)
                  Divider(
                    height: 3,
                    thickness: 3,
                    color: context.auraBackground,
                  ),
                widget.children[index],
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
    this.pending = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool pending;
  @override
  Widget build(BuildContext context) => ListTile(
    enabled: onTap != null,
    minTileHeight: 62,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    leading: Icon(
      icon,
      size: 22,
      color: onTap == null
          ? context.auraMuted.withValues(alpha: .5)
          : context.auraOnSurface,
    ),
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 15),
    ),
    subtitle: pending
        ? Text(
            'În pregătire',
            style: TextStyle(color: context.auraMuted, fontSize: 11),
          )
        : subtitle == null
        ? null
        : Text(
            subtitle!,
            style: TextStyle(color: context.auraMuted, fontSize: 12),
          ),
    onTap: onTap,
  );
}
