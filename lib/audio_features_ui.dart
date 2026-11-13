part of 'main.dart';

enum _AudioFeaturePage {
  transitions,
  equalizer,
  commands,
  headset,
  notification,
  focus,
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
        backgroundColor: context.auraBackground,
        title: Text(switch (widget.page) {
          _AudioFeaturePage.transitions => context.appStrings.uiTransitions,
          _AudioFeaturePage.equalizer => context.appStrings.uiEqualizer,
          _AudioFeaturePage.commands => context.appStrings.uiMediaControls,
          _AudioFeaturePage.headset => context.appStrings.uiHeadsetButtons,
          _AudioFeaturePage.notification =>
            context.appStrings.uiNotificationButtons,
          _AudioFeaturePage.focus => context.appStrings.uiAudioFocus,
        }),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.page == _AudioFeaturePage.focus)
            _SettingsGroup(
              title: context.appStrings.uiAudioFocus,
              children: [
                SwitchListTile(
                  title: Text(context.appStrings.focusPauseForInterruption),
                  subtitle: Text(context.appStrings.focusPauseDescription),
                  value: features.pauseWhenDucked,
                  onChanged:
                      enabled &&
                          !kIsWeb &&
                          defaultTargetPlatform == TargetPlatform.android
                      ? (value) => _save(features.copy(pauseWhenDucked: value))
                      : null,
                ),
                if (kIsWeb || defaultTargetPlatform != TargetPlatform.android)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(context.appStrings.focusAndroidOnly),
                  ),
              ],
            ),
          if (widget.page == _AudioFeaturePage.transitions) ...[
            _SettingsGroup(
              title: context.appStrings.uiCrossfade,
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
                            ? context.appStrings.uiOff
                            : context.appStrings.secondsValue(
                                (_crossfadePreview ?? features.crossfadeSeconds)
                                    .round(),
                              ),
                      ),
                      Slider(
                        min: 0,
                        max: 10,
                        divisions: 10,
                        label: context.appStrings.secondsShort(
                          context.number(
                            (_crossfadePreview ?? features.crossfadeSeconds)
                                .round(),
                          ),
                        ),
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
                      Text(
                        context.appStrings.uiOverlapsTheEndOfATrackWith,
                        style: TextStyle(
                          color: context.auraMuted,
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
              title: context.appStrings.uiPlayAndPause,
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
                                ? context.appStrings.uiNoFade
                                : context.appStrings.secondsShort(
                                    context.number(milliseconds / 1000),
                                  ),
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
              title: context.appStrings.uiNotificationAndLockScreen,
              children: [
                SwitchListTile(
                  title: Text(context.appStrings.uiSeekButtons10Seconds),
                  subtitle: Text(
                    context
                        .appStrings
                        .uiReplacesPreviousnextWithSeekingInTheNotification,
                  ),
                  value: features.seekButtons,
                  onChanged: enabled
                      ? (value) => _save(features.copy(seekButtons: value))
                      : null,
                ),
                SwitchListTile(
                  title: Text(context.appStrings.uiShowStopButton),
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
              title: context.appStrings.uiHeadsetAndMediaButtons,
              children: [
                SwitchListTile(
                  title: Text(context.appStrings.uiSeek10SecondsFromHeadset),
                  subtitle: Text(
                    context
                        .appStrings
                        .uiPreviousnextButtonsSeekWithinTheCurrentTrack,
                  ),
                  value: features.headsetSeek,
                  onChanged: enabled
                      ? (value) => _save(features.copy(headsetSeek: value))
                      : null,
                ),
                SwitchListTile(
                  title: Text(
                    context.appStrings.uiKeepPausedWhenChangingTracks,
                  ),
                  value: features.keepPausedOnSkip,
                  onChanged: enabled
                      ? (value) => _save(features.copy(keepPausedOnSkip: value))
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              context.appStrings.uiNotificationAndHeadsetControlsAreAvailableOn,
              style: TextStyle(color: context.auraMuted, fontSize: 12),
            ),
          ],
          if (widget.page == _AudioFeaturePage.equalizer)
            FutureBuilder<AndroidEqualizerParameters?>(
              future: _parameters,
              builder: (context, snapshot) {
                if (!_audioRuntime.isAndroid) {
                  return Text(
                    context
                        .appStrings
                        .uiTheEqualizerIsCurrentlyAvailableOnAndroid,
                  );
                }
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final parameters = snapshot.data;
                if (parameters == null) {
                  return Text(
                    context.appStrings.uiSelectATrackAndReopenTheEqualizer,
                  );
                }
                return _SettingsGroup(
                  title: context.appStrings.uiAndroidEqualizer,
                  children: [
                    SwitchListTile(
                      title: Text(context.appStrings.uiEnableEqualizer),
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
                          for (final preset in [0, 1, 2])
                            ActionChip(
                              label: Text(switch (preset) {
                                1 => context.appStrings.uiBass,
                                2 => context.appStrings.uiVoice,
                                _ => context.appStrings.uiFlat,
                              }),
                              onPressed: enabled
                                  ? () => _save(
                                      features.copy(
                                        bandGains: parameters.bands
                                            .map(
                                              (band) => switch (preset) {
                                                1 =>
                                                  band.centerFrequency < 250
                                                      ? 4.0
                                                      : 0.0,
                                                2 =>
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
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        context
                            .appStrings
                            .uiWhenBoostingABandAuraAutomaticallyReduces,
                        style: TextStyle(
                          color: context.auraMuted,
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
