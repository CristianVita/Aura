part of 'main.dart';

void _settingsHelp(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(context.appStrings.uiAuraSettings),
    content: Text(context.appStrings.uiOptionsMarkedComingSoonAreNotAvailable),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.appStrings.uiGotIt),
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
            tooltip: context.appStrings.uiHelp,
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
    this.onGenerated,
    this.onOfflineFiles,
    required this.onManageSources,
    required this.onScan,
    required this.isScanning,
  });
  final String sourceSummary;
  final PlaybackSettingsController controls;
  final VoidCallback onFilters, onHistory, onManageSources, onScan;
  final VoidCallback? onBackup, onOfflineFiles, onGenerated;
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
            tooltip: context.appStrings.uiHelp,
            onPressed: () => _settingsHelp(context),
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      const SizedBox(height: 20),
      _SettingsGroup(
        title: context.appStrings.navigationSettings,
        children: [
          _SettingsRow(
            icon: Icons.touch_app_outlined,
            title: context.appStrings.uiInterface,
            onTap: () => _settingsPage(
              context,
              context.appStrings.uiInterfaceSettings,
              (context) => [
                _SettingsGroup(
                  title: context.appStrings.uiApplicationStyle,
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
                  title: context.appStrings.uiGeneral,
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
                      title: context.appStrings.uiMediaLists,
                      onTap: filtersReady ? onFilters : null,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SettingsGroup(
                  title: context.appStrings.uiNowPlayingScreens,
                  collapsible: true,
                  children: [
                    _SettingsRow(
                      icon: Icons.play_circle_outline,
                      title: context.appStrings.uiNowPlayingScreen,
                      onTap: () => _settingsPage(
                        context,
                        context.appStrings.uiNowPlayingScreen,
                        (context) => [
                          _SettingsGroup(
                            title: context.appStrings.uiTrackRatings,
                            children: [
                              Padding(
                                padding: EdgeInsets.all(8),
                                child: RatingSizeSettings(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            context.appStrings.uiSwipeAcrossTheStarsToRateIn399,
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
                  title: context.appStrings.uiPageSettings,
                  collapsible: true,
                  children: [
                    _SettingsRow(
                      icon: Icons.home_outlined,
                      title: context.appStrings.uiHomePage,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const HomePageSettings(),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.library_music_outlined,
                      title: context.appStrings.libraryPageTitle,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LibraryPageSettings(
                            page: LibraryPageKind.library,
                          ),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.album_outlined,
                      title: context.appStrings.albumPageTitle,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LibraryPageSettings(
                            page: LibraryPageKind.albums,
                          ),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.person_outline,
                      title: context.appStrings.artistPageTitle,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LibraryPageSettings(
                            page: LibraryPageKind.artists,
                          ),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.style_outlined,
                      title: context.appStrings.uiGenrePage,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LibraryPageSettings(
                            page: LibraryPageKind.genres,
                          ),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.queue_music,
                      title: context.appStrings.uiPlaylistPage,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PlaylistPageSettings(),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.search,
                      title: context.appStrings.uiSearchPage,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SearchPageSettings(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SettingsGroup(
                  title: context.appStrings.uiAdvanced,
                  collapsible: true,
                  children: [
                    _SettingsRow(
                      icon: Icons.settings_outlined,
                      title: context.appStrings.uiAdvancedInterfaceSettings,
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
            title: context.appStrings.uiPlayback,
            onTap: () => _settingsPage(
              context,
              context.appStrings.uiPlaybackSettings,
              (context) => [
                _SettingsGroup(
                  title: '',
                  children: [
                    _SettingsRow(
                      icon: Icons.headphones_outlined,
                      title: context.appStrings.uiOutputSettings,
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
                      title: context.appStrings.uiPlayback,
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
                      title: context.appStrings.uiAutomaticActions,
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
                      title: context.appStrings.uiDecodingAndTranscoding,
                      onTap: null,
                      pending: true,
                    ),
                    _SettingsRow(
                      icon: Icons.compare_arrows,
                      title: context.appStrings.uiTransitions,
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
                      title: context.appStrings.uiAudioFocus,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const _AudioFeatureSettings(
                            page: _AudioFeaturePage.focus,
                          ),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.headphones_outlined,
                      title: context.appStrings.uiHeadsetButtons,
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
                      title: context
                          .appStrings
                          .uiNotificationAndMediaSessionButtons,
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
                      title: context.appStrings.uiAdvancedPlaybackSettings,
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
            title: context.appStrings.uiOfflineCacheAndDownloads,
            onTap: () => _settingsPage(
              context,
              context.appStrings.uiOfflineCacheAndDownloads,
              (context) => [
                _SettingsGroup(
                  title: '',
                  children: [
                    _SettingsRow(
                      icon: Icons.download_outlined,
                      title: context.appStrings.uiGeneral,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DownloadNetworkSettings(
                            policy: AudioLibrary.downloadNetwork,
                          ),
                        ),
                      ),
                    ),
                    if (!kIsWeb &&
                        defaultTargetPlatform == TargetPlatform.android)
                      _SettingsRow(
                        icon: Icons.downloading,
                        title: context.appStrings.backgroundTitle,
                        onTap: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BackgroundDownloadsScreen(),
                          ),
                        ),
                      ),
                    _SettingsRow(
                      icon: Icons.music_note_outlined,
                      title: context.appStrings.uiMedia,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OfflineMediaSettings(
                            store: AudioLibrary.offline,
                            cache: playbackCache,
                            onOpenDownloads: onOfflineFiles,
                          ),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.play_arrow_outlined,
                      title: context.appStrings.uiOfflineServerPlayback,
                      onTap: onOfflineFiles,
                      pending: onOfflineFiles == null,
                    ),
                    _SettingsRow(
                      icon: Icons.image_outlined,
                      title: context.appStrings.uiImages,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ArtworkCacheSettings(cache: artworkMemoryCache),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  context.appStrings.offlineSettingsHelp,
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
            title: context.appStrings.uiAdvanced,
            onTap: () => _settingsPage(
              context,
              context.appStrings.uiAdvancedSettings,
              (context) => [
                _SettingsGroup(
                  title: context.appStrings.uiLibrary,
                  children: [
                    _SettingsRow(
                      icon: Icons.filter_alt_outlined,
                      title: context.appStrings.uiLibraryFilters,
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
        title: context.appStrings.uiMiscellaneous,
        children: [
          _SettingsRow(
            icon: Icons.devices_outlined,
            title: context.appStrings.uiMediaSources,
            onTap: isScanning ? null : onManageSources,
          ),
          _SettingsRow(
            icon: Icons.sync,
            title: context.appStrings.uiSyncManager,
            onTap: () => _settingsPage(
              context,
              context.appStrings.uiSyncManager,
              (context) => [
                _SettingsGroup(
                  title: context.appStrings.uiLibrary,
                  children: [
                    _SettingsRow(
                      icon: Icons.sync,
                      title: isScanning
                          ? context.appStrings.uiUpdating
                          : context.appStrings.uiRefreshLibrary,
                      subtitle: sourceSummary,
                      onTap: isScanning ? null : onScan,
                    ),
                    _SettingsRow(
                      icon: Icons.dns_outlined,
                      title: context.appStrings.uiRefreshNavidromeSources,
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
            title: context.appStrings.uiOfflineFiles,
            onTap: onOfflineFiles,
            pending: onOfflineFiles == null,
          ),
          _SettingsRow(
            icon: Icons.folder_copy_outlined,
            title: context.appStrings.uiGeneratedFiles,
            onTap: onGenerated,
            pending: onGenerated == null,
          ),
          _SettingsRow(
            icon: Icons.settings_backup_restore,
            title: context.appStrings.uiBackupAndRestore,
            onTap: onBackup,
            pending: onBackup == null,
          ),
          _SettingsRow(
            icon: Icons.history,
            title: context.appStrings.uiListeningHistory,
            onTap: onHistory,
          ),
          _SettingsRow(
            icon: Icons.translate,
            title: context.appStrings.uiLanguages,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const LanguageSettingsScreen()),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      _SettingsGroup(
        title: context.appStrings.uiAbout,
        children: [
          _SettingsRow(
            icon: Icons.star_border,
            title: context.appStrings.uiRateTheApp,
            onTap: null,
            pending: true,
          ),
          _SettingsRow(
            icon: Icons.help_outline,
            title: context.appStrings.uiHelp,
            onTap: () => _settingsHelp(context),
          ),
          _SettingsRow(
            icon: Icons.support_agent,
            title: context.appStrings.uiContactSupport,
            onTap: null,
            pending: true,
          ),
          _SettingsRow(
            icon: Icons.description_outlined,
            title: context.appStrings.uiWhatsNew,
            onTap: () => _settingsPage(
              context,
              context.appStrings.uiWhatsNewInAura,
              (context) => [
                Text(
                  context
                      .appStrings
                      .uiLocalAndNavidromeLibrariesHalfstarRatingsHistory,
                  style: TextStyle(height: 1.8),
                ),
              ],
            ),
          ),
          _SettingsRow(
            icon: Icons.info_outline,
            title: context.appStrings.uiAboutAura,
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Aura',
              applicationIcon: const AuraLogo(size: 48),
              children: [
                Text(context.appStrings.uiAPlayerForYourLocalMusicAnd),
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
            context.appStrings.uiComingSoon,
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
