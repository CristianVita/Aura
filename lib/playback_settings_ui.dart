part of 'main.dart';

String _sleepLabel(BuildContext context, SleepTimerController sleep) {
  if (!sleep.active) return context.appStrings.uiOff;
  if (sleep.waitingForTrack) return context.appStrings.uiAtTheEndOfTheTrack;
  final seconds = sleep.remaining.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

Future<void> _showSleepTimer(
  BuildContext context,
  PlaybackSettingsController controls,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: context.auraSurface,
  builder: (_) => _SleepTimerSheet(controls: controls),
);

class _SleepTimerSheet extends StatefulWidget {
  const _SleepTimerSheet({required this.controls});
  final PlaybackSettingsController controls;
  @override
  State<_SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<_SleepTimerSheet> {
  int _minutes = 15;
  bool _finish = false;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.appStrings.uiSleepTimer,
                  style: TextStyle(fontSize: 21),
                ),
              ),
              IconButton(
                tooltip: context.appStrings.uiCloseSleepTimer,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          ListenableBuilder(
            listenable: widget.controls.sleep,
            builder: (_, child) => Text(
              context.appStrings.activeTimer(
                _sleepLabel(context, widget.controls.sleep),
              ),
              style: TextStyle(color: context.auraAccent),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            context.appStrings.minutesValue(_minutes),
            style: const TextStyle(fontSize: 24),
          ),
          Slider(
            label: context.appStrings.minutesValue(_minutes),
            min: 5,
            max: 120,
            divisions: 23,
            value: _minutes.toDouble(),
            onChanged: (value) => setState(() => _minutes = value.round()),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final minutes in [5, 15, 30, 60])
                ChoiceChip(
                  label: Text(context.appStrings.minutesShort(minutes)),
                  selected: _minutes == minutes,
                  onSelected: (_) => setState(() => _minutes = minutes),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.appStrings.uiFinishTheCurrentTrack),
            subtitle: Text(context.appStrings.uiWhenTheTimerEndsWaitForThe),
            value: _finish,
            onChanged: (value) => setState(() => _finish = value),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.bedtime_outlined),
              label: Text(context.appStrings.uiStartSleepTimer),
              onPressed: () {
                widget.controls.sleep.start(
                  Duration(minutes: _minutes),
                  finishTrack: _finish,
                );
                Navigator.pop(context);
              },
            ),
          ),
          TextButton(
            onPressed: widget.controls.player.sequence.isEmpty
                ? null
                : () {
                    widget.controls.sleep.stopAfterTrack();
                    Navigator.pop(context);
                  },
            child: Text(context.appStrings.uiStopAtTheEndOfThisTrack),
          ),
          ListenableBuilder(
            listenable: widget.controls.sleep,
            builder: (_, child) => widget.controls.sleep.active
                ? TextButton(
                    onPressed: () {
                      widget.controls.sleep.cancel();
                      Navigator.pop(context);
                    },
                    child: Text(context.appStrings.uiCancelSleepTimer),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    ),
  );
}

enum PlaybackSettingsSection { all, output, playback, timer }

class PlaybackSettingsScreen extends StatefulWidget {
  const PlaybackSettingsScreen({
    super.key,
    required this.controls,
    this.section = PlaybackSettingsSection.all,
  });
  final PlaybackSettingsController controls;
  final PlaybackSettingsSection section;
  @override
  State<PlaybackSettingsScreen> createState() => _PlaybackSettingsScreenState();
}

class _PlaybackSettingsScreenState extends State<PlaybackSettingsScreen> {
  bool _busy = false;
  double? _speed, _volume;
  Future<void> _change({double? speed, double? volume}) async {
    setState(() => _busy = true);
    await saveMusicAction(
      context,
      () => widget.controls.change(speed: speed, volume: volume),
    );
    if (mounted) {
      setState(() {
        _busy = false;
        _speed = null;
        _volume = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = SavedMusicScope.of(context);
    final speed = _speed ?? store.data.playbackSpeed;
    final volume = _volume ?? store.data.playbackVolume;
    final enabled = store.ready && !_busy;
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (widget.section) {
          PlaybackSettingsSection.all => context.appStrings.uiPlaybackSettings,
          PlaybackSettingsSection.output => context.appStrings.uiOutputSettings,
          PlaybackSettingsSection.playback => context.appStrings.uiPlayback,
          PlaybackSettingsSection.timer =>
            context.appStrings.uiAutomaticActions,
        }),
        backgroundColor: context.auraBackground,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.section == PlaybackSettingsSection.all ||
              widget.section == PlaybackSettingsSection.output)
            _SettingsGroup(
              title: context.appStrings.uiAudioOutput,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.appStrings.playerVolume((volume * 100).round()),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context
                            .appStrings
                            .uiOnlyAppliesInAuraSeparatelyFromYour,
                        style: TextStyle(
                          color: context.auraMuted,
                          fontSize: 12,
                        ),
                      ),
                      Slider(
                        label: context.appStrings.percentValue(
                          (volume * 100).round(),
                        ),
                        value: volume,
                        divisions: 100,
                        onChanged: enabled
                            ? (value) => setState(() => _volume = value)
                            : null,
                        onChangeEnd: enabled
                            ? (value) => _change(volume: value)
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
          if (widget.section == PlaybackSettingsSection.all ||
              widget.section == PlaybackSettingsSection.playback)
            _SettingsGroup(
              title: context.appStrings.uiPlayback,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.appStrings.playbackSpeed(
                          context.number(speed, digits: 2),
                        ),
                      ),
                      Slider(
                        label: '${context.number(speed, digits: 2)}×',
                        min: .5,
                        max: 2,
                        divisions: 30,
                        value: speed,
                        onChanged: enabled
                            ? (value) => setState(() => _speed = value)
                            : null,
                        onChangeEnd: enabled
                            ? (value) => _change(speed: value)
                            : null,
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final value in [.75, 1.0, 1.25, 1.5, 2.0])
                            ChoiceChip(
                              label: Text(
                                '${context.number(value, digits: 2)}×',
                              ),
                              selected: (speed - value).abs() < .001,
                              onSelected: enabled
                                  ? (_) => _change(speed: value)
                                  : null,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
          if (widget.section == PlaybackSettingsSection.all ||
              widget.section == PlaybackSettingsSection.timer)
            ListenableBuilder(
              listenable: widget.controls.sleep,
              builder: (_, child) => _SettingsGroup(
                title: context.appStrings.uiTimer,
                children: [
                  _SettingsRow(
                    icon: Icons.bedtime_outlined,
                    title: context.appStrings.uiSleepTimer,
                    subtitle: _sleepLabel(context, widget.controls.sleep),
                    onTap: () => _showSleepTimer(context, widget.controls),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          if (widget.section == PlaybackSettingsSection.all ||
              widget.section == PlaybackSettingsSection.output)
            _SettingsGroup(
              title: context.appStrings.uiAudioOptions,
              children: [
                if (widget.section == PlaybackSettingsSection.all)
                  _SettingsRow(
                    icon: Icons.compare_arrows_rounded,
                    title: context.appStrings.uiTransitions,
                    subtitle: context.appStrings.uiCrossfadeAndPlaypauseFades,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const _AudioFeatureSettings(
                          page: _AudioFeaturePage.transitions,
                        ),
                      ),
                    ),
                  ),
                _SettingsRow(
                  icon: Icons.equalizer_rounded,
                  title: context.appStrings.uiEqualizer,
                  subtitle: Theme.of(context).platform == TargetPlatform.android
                      ? context.appStrings.uiFrequencyBandsAndPresets
                      : context.appStrings.uiAvailableOnAndroid,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const _AudioFeatureSettings(
                        page: _AudioFeaturePage.equalizer,
                      ),
                    ),
                  ),
                ),
                if (widget.section == PlaybackSettingsSection.all)
                  _SettingsRow(
                    icon: Icons.headphones_outlined,
                    title: context.appStrings.uiMediaControls,
                    subtitle:
                        context.appStrings.uiNotificationLockScreenAndHeadset,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const _AudioFeatureSettings(
                          page: _AudioFeaturePage.commands,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 20),
          if (widget.section == PlaybackSettingsSection.all)
            TextButton(
              onPressed: enabled ? () => _change(speed: 1, volume: 1) : null,
              child: Text(context.appStrings.uiRestoreDefaultSpeedAndVolume),
            ),
          const SizedBox(height: 8),
          Text(
            context.appStrings.uiSpeedAndVolumeAreSavedOnThis,
            style: TextStyle(
              color: context.auraMuted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackQuickSettings extends StatelessWidget {
  const _PlaybackQuickSettings({required this.controls});
  final PlaybackSettingsController controls;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controls.sleep,
    builder: (_, child) {
      final sleepLabel = controls.sleep.active
          ? _sleepLabel(context, controls.sleep)
          : context.appStrings.uiSleep;
      final speed = context.number(
        SavedMusicScope.of(context).data.playbackSpeed,
        digits: 2,
      );
      void openSettings() => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PlaybackSettingsScreen(controls: controls),
        ),
      );
      return PlayerQuickActions(
        sleepLabel: sleepLabel,
        sleepTooltip: '${context.appStrings.uiSleepTimer}: $sleepLabel',
        sleepActive: controls.sleep.active,
        speedLabel: '$speed×',
        speedTooltip: context.appStrings.playbackSpeed(speed),
        equalizerTooltip: context.appStrings.uiEqualizer,
        settingsTooltip: context.appStrings.uiPlaybackSettings,
        onSleep: () => _showSleepTimer(context, controls),
        onSpeed: openSettings,
        onEqualizer: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                const _AudioFeatureSettings(page: _AudioFeaturePage.equalizer),
          ),
        ),
        onSettings: openSettings,
      );
    },
  );
}
