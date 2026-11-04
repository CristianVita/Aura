part of 'main.dart';

enum _AudioFeaturePage {
  transitions,
  equalizer,
  commands,
  headset,
  notification,
}

class _AudioFeatureSettings extends StatefulWidget {
  const _AudioFeatureSettings({required this.page});
  final _AudioFeaturePage page;
  @override
  State<_AudioFeatureSettings> createState() => _AudioFeatureSettingsState();
}

class _AudioFeatureSettingsState extends State<_AudioFeatureSettings> {
  bool _busy = false;
  double? _crossfadePreview;
  final _bandPreviews = <int, double>{};
  late final Future<AndroidEqualizerParameters?> _parameters =
      widget.page == _AudioFeaturePage.equalizer
      ? _audioRuntime.equalizerParameters()
      : Future.value(null);
  Future<void> _save(AudioFeatures next) async {
    setState(() => _busy = true);
    await saveMusicAction(context, () => _audioRuntime.changeFeatures(next));
    if (mounted) {
      setState(() {
        _busy = false;
        _crossfadePreview = null;
        _bandPreviews.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = SavedMusicScope.of(context);
    final features = store.data.audioFeatures;
    final enabled = store.ready && !_busy;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _background,
        title: Text(switch (widget.page) {
          _AudioFeaturePage.transitions => 'Tranziții',
          _AudioFeaturePage.equalizer => 'Egalizator',
          _AudioFeaturePage.commands => 'Comenzi media',
          _AudioFeaturePage.headset => 'Butoanele căștilor',
          _AudioFeaturePage.notification => 'Butoane notificare',
        }),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.page == _AudioFeaturePage.transitions) ...[
            _SettingsGroup(
              title: 'Crossfade',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (_crossfadePreview ?? features.crossfadeSeconds)
                                    .round() ==
                                0
                            ? 'Oprit'
                            : '${(_crossfadePreview ?? features.crossfadeSeconds).round()} secunde',
                      ),
                      Slider(
                        min: 0,
                        max: 10,
                        divisions: 10,
                        label:
                            '${(_crossfadePreview ?? features.crossfadeSeconds).round()} s',
                        value:
                            _crossfadePreview ??
                            features.crossfadeSeconds.toDouble(),
                        onChanged: enabled
                            ? (value) =>
                                  setState(() => _crossfadePreview = value)
                            : null,
                        onChangeEnd: enabled
                            ? (value) => _save(
                                features.copy(crossfadeSeconds: value.round()),
                              )
                            : null,
                      ),
                      const Text(
                        'Suprapune sfârșitul piesei cu începutul următoarei la avansare automată. Piesele foarte scurte și repetarea unei singure piese nu folosesc crossfade.',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 12,
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
              title: 'Pornire și pauză',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final milliseconds in [0, 250, 500, 1000, 2000])
                        ChoiceChip(
                          label: Text(
                            milliseconds == 0
                                ? 'Fără fade'
                                : '${milliseconds / 1000} s',
                          ),
                          selected: features.fadeMilliseconds == milliseconds,
                          onSelected: enabled
                              ? (_) => _save(
                                  features.copy(fadeMilliseconds: milliseconds),
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (widget.page == _AudioFeaturePage.commands ||
              widget.page == _AudioFeaturePage.notification) ...[
            _SettingsGroup(
              title: 'Notificare și ecran blocat',
              children: [
                SwitchListTile(
                  title: const Text('Butoane de salt ±10 secunde'),
                  subtitle: const Text(
                    'Înlocuiește anterior/următor cu derulare în notificare.',
                  ),
                  value: features.seekButtons,
                  onChanged: enabled
                      ? (value) => _save(features.copy(seekButtons: value))
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Arată butonul Stop'),
                  value: features.showStop,
                  onChanged: enabled
                      ? (value) => _save(features.copy(showStop: value))
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
          if (widget.page == _AudioFeaturePage.commands ||
              widget.page == _AudioFeaturePage.headset) ...[
            _SettingsGroup(
              title: 'Căști și butoane media',
              children: [
                SwitchListTile(
                  title: const Text('Salt ±10 secunde din căști'),
                  subtitle: const Text(
                    'Butoanele anterior/următor derulează în piesa curentă. Butonul central păstrează Redă/Pauză.',
                  ),
                  value: features.headsetSeek,
                  onChanged: enabled
                      ? (value) => _save(features.copy(headsetSeek: value))
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Păstrează pauza la schimbarea piesei'),
                  value: features.keepPausedOnSkip,
                  onChanged: enabled
                      ? (value) => _save(features.copy(keepPausedOnSkip: value))
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Comenzile din notificare și căști sunt disponibile pe Android. Unele sisteme rearanjează butoanele notificării.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
          if (widget.page == _AudioFeaturePage.equalizer)
            FutureBuilder<AndroidEqualizerParameters?>(
              future: _parameters,
              builder: (context, snapshot) {
                if (!_audioRuntime.isAndroid) {
                  return const Text(
                    'Egalizatorul este disponibil momentan pe Android.',
                  );
                }
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final parameters = snapshot.data;
                if (parameters == null) {
                  return const Text(
                    'Selectează o piesă și redeschide egalizatorul. Dacă tot nu este disponibil, dispozitivul nu expune efectul audio necesar.',
                  );
                }
                return _SettingsGroup(
                  title: 'Egalizator Android',
                  children: [
                    SwitchListTile(
                      title: const Text('Activează egalizatorul'),
                      value: features.equalizerEnabled,
                      onChanged: enabled
                          ? (value) =>
                                _save(features.copy(equalizerEnabled: value))
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final preset in ['Plat', 'Bass', 'Voce'])
                            ActionChip(
                              label: Text(preset),
                              onPressed: enabled
                                  ? () => _save(
                                      features.copy(
                                        bandGains: parameters.bands
                                            .map(
                                              (band) => switch (preset) {
                                                'Bass' =>
                                                  band.centerFrequency < 250
                                                      ? 4.0
                                                      : 0.0,
                                                'Voce' =>
                                                  band.centerFrequency >= 300 &&
                                                          band.centerFrequency <=
                                                              4000
                                                      ? 3.0
                                                      : -2.0,
                                                _ => 0.0,
                                              },
                                            )
                                            .map(
                                              (gain) => gain.clamp(
                                                parameters.minDecibels,
                                                parameters.maxDecibels,
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    )
                                  : null,
                            ),
                        ],
                      ),
                    ),
                    for (final band in parameters.bands)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${band.centerFrequency >= 1000 ? '${(band.centerFrequency / 1000).toStringAsFixed(1)} kHz' : '${band.centerFrequency.round()} Hz'} · ${(_bandPreviews[band.index] ?? (band.index < features.bandGains.length ? features.bandGains[band.index] : 0)).toStringAsFixed(1)} dB',
                            ),
                            Slider(
                              min: parameters.minDecibels,
                              max: parameters.maxDecibels,
                              value:
                                  (_bandPreviews[band.index] ??
                                          (band.index <
                                                  features.bandGains.length
                                              ? features.bandGains[band.index]
                                              : 0.0))
                                      .clamp(
                                        parameters.minDecibels,
                                        parameters.maxDecibels,
                                      ),
                              onChanged: enabled
                                  ? (value) => setState(
                                      () => _bandPreviews[band.index] = value,
                                    )
                                  : null,
                              onChangeEnd: enabled
                                  ? (value) {
                                      final gains = List<double>.generate(
                                        parameters.bands.length,
                                        (index) =>
                                            index < features.bandGains.length
                                            ? features.bandGains[index]
                                            : 0,
                                      );
                                      gains[band.index] = value;
                                      _save(features.copy(bandGains: gains));
                                    }
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Când amplifici o bandă, Aura reduce automat nivelul general pentru a păstra rezervă de volum și a limita distorsiunea.',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
