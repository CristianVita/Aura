part of 'main.dart';

String _sleepLabel(SleepTimerController sleep) {
  if (!sleep.active) return 'Oprit';
  if (sleep.waitingForTrack) return 'La sfârșitul piesei';
  final seconds = sleep.remaining.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

Future<void> _showSleepTimer(
  BuildContext context,
  PlaybackSettingsController controls,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: _surface,
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
              const Expanded(
                child: Text(
                  'Temporizator de oprire',
                  style: TextStyle(fontSize: 21),
                ),
              ),
              IconButton(
                tooltip: 'Închide temporizatorul',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          ListenableBuilder(
            listenable: widget.controls.sleep,
            builder: (_, child) => Text(
              'Activ: ${_sleepLabel(widget.controls.sleep)}',
              style: const TextStyle(color: _mint),
            ),
          ),
          const SizedBox(height: 20),
          Text('$_minutes minute', style: const TextStyle(fontSize: 24)),
          Slider(
            label: '$_minutes minute',
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
                  label: Text('$minutes min'),
                  selected: _minutes == minutes,
                  onSelected: (_) => setState(() => _minutes = minutes),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Termină piesa curentă'),
            subtitle: const Text(
              'La expirare, așteaptă sfârșitul piesei înainte de pauză.',
            ),
            value: _finish,
            onChanged: (value) => setState(() => _finish = value),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.bedtime_outlined),
              label: const Text('Pornește temporizatorul'),
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
            child: const Text('Oprește la sfârșitul acestei piese'),
          ),
          ListenableBuilder(
            listenable: widget.controls.sleep,
            builder: (_, child) => widget.controls.sleep.active
                ? TextButton(
                    onPressed: () {
                      widget.controls.sleep.cancel();
                      Navigator.pop(context);
                    },
                    child: const Text('Anulează temporizatorul'),
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
          PlaybackSettingsSection.all => 'Setări de redare',
          PlaybackSettingsSection.output => 'Setări de ieșire',
          PlaybackSettingsSection.playback => 'Redare',
          PlaybackSettingsSection.timer => 'Acțiuni automate',
        }),
        backgroundColor: _background,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.section == PlaybackSettingsSection.all ||
              widget.section == PlaybackSettingsSection.output)
            _SettingsGroup(
              title: 'Ieșire audio',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Volumul playerului: ${(volume * 100).round()}%'),
                      const SizedBox(height: 6),
                      const Text(
                        'Se aplică doar în Aura, separat de volumul telefonului sau al PC-ului.',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                      Slider(
                        label: '${(volume * 100).round()}%',
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
              title: 'Redare',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Viteză: ${speed.toStringAsFixed(2)}×'),
                      Slider(
                        label: '${speed.toStringAsFixed(2)}×',
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
                              label: Text('${value.toStringAsFixed(2)}×'),
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
                title: 'Temporizator',
                children: [
                  _SettingsRow(
                    icon: Icons.bedtime_outlined,
                    title: 'Temporizator de oprire',
                    subtitle: _sleepLabel(widget.controls.sleep),
                    onTap: () => _showSleepTimer(context, widget.controls),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          if (widget.section == PlaybackSettingsSection.all ||
              widget.section == PlaybackSettingsSection.output)
            _SettingsGroup(
              title: 'Opțiuni audio',
              children: [
                if (widget.section == PlaybackSettingsSection.all)
                  _SettingsRow(
                    icon: Icons.compare_arrows_rounded,
                    title: 'Tranziții',
                    subtitle: 'Crossfade și fade la pornire/pauză',
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
                  title: 'Egalizator',
                  subtitle: Theme.of(context).platform == TargetPlatform.android
                      ? 'Benzi de frecvență și preseturi'
                      : 'Disponibil pe Android',
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
                    title: 'Comenzi media',
                    subtitle: 'Notificare, ecran blocat și căști',
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
              child: const Text('Restabilește viteza și volumul implicite'),
            ),
          const SizedBox(height: 8),
          const Text(
            'Viteza și volumul sunt salvate pe acest dispozitiv. Temporizatorul se anulează la închiderea completă a aplicației.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
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
    builder: (_, child) => Row(
      children: [
        Expanded(
          child: TextButton.icon(
            icon: Icon(
              Icons.bedtime_outlined,
              color: controls.sleep.active ? _mint : _muted,
            ),
            label: Text(
              controls.sleep.active ? _sleepLabel(controls.sleep) : 'Somn',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: () => _showSleepTimer(context, controls),
          ),
        ),
        Expanded(
          child: TextButton.icon(
            icon: const Icon(Icons.speed_rounded),
            label: Text(
              '${SavedMusicScope.of(context).data.playbackSpeed.toStringAsFixed(2)}×',
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => PlaybackSettingsScreen(controls: controls),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Egalizator',
          icon: const Icon(Icons.equalizer_rounded),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const _AudioFeatureSettings(
                page: _AudioFeaturePage.equalizer,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Setări de redare',
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => PlaybackSettingsScreen(controls: controls),
            ),
          ),
        ),
      ],
    ),
  );
}
