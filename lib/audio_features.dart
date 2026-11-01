class AudioFeatures {
  const AudioFeatures({
    this.crossfadeSeconds = 0,
    this.fadeMilliseconds = 0,
    this.equalizerEnabled = false,
    this.bandGains = const [],
    this.seekButtons = false,
    this.headsetSeek = false,
    this.showStop = true,
    this.keepPausedOnSkip = true,
  });
  final int crossfadeSeconds, fadeMilliseconds;
  final bool equalizerEnabled,
      seekButtons,
      headsetSeek,
      showStop,
      keepPausedOnSkip;
  final List<double> bandGains;
  AudioFeatures copy({
    int? crossfadeSeconds,
    int? fadeMilliseconds,
    bool? equalizerEnabled,
    List<double>? bandGains,
    bool? seekButtons,
    bool? headsetSeek,
    bool? showStop,
    bool? keepPausedOnSkip,
  }) => AudioFeatures(
    crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
    fadeMilliseconds: fadeMilliseconds ?? this.fadeMilliseconds,
    equalizerEnabled: equalizerEnabled ?? this.equalizerEnabled,
    bandGains: List.unmodifiable(bandGains ?? this.bandGains),
    seekButtons: seekButtons ?? this.seekButtons,
    headsetSeek: headsetSeek ?? this.headsetSeek,
    showStop: showStop ?? this.showStop,
    keepPausedOnSkip: keepPausedOnSkip ?? this.keepPausedOnSkip,
  );
  Map<String, Object> toJson() => {
    'crossfadeSeconds': crossfadeSeconds,
    'fadeMilliseconds': fadeMilliseconds,
    'equalizerEnabled': equalizerEnabled,
    'bandGains': bandGains,
    'seekButtons': seekButtons,
    'headsetSeek': headsetSeek,
    'showStop': showStop,
    'keepPausedOnSkip': keepPausedOnSkip,
  };
  factory AudioFeatures.fromJson(Map<String, dynamic> value) {
    final seconds = value['crossfadeSeconds'] ?? 0,
        fade = value['fadeMilliseconds'] ?? 0;
    final gains = (value['bandGains'] as List? ?? [])
        .map((v) => (v as num).toDouble())
        .toList();
    if (seconds is! int ||
        seconds < 0 ||
        seconds > 10 ||
        fade is! int ||
        fade < 0 ||
        fade > 2000 ||
        gains.length > 32 ||
        gains.any((g) => !g.isFinite || g.abs() > 15)) {
      throw const FormatException('Invalid audio features');
    }
    return AudioFeatures(
      crossfadeSeconds: seconds,
      fadeMilliseconds: fade,
      equalizerEnabled: value['equalizerEnabled'] as bool? ?? false,
      bandGains: List.unmodifiable(gains),
      seekButtons: value['seekButtons'] as bool? ?? false,
      headsetSeek: value['headsetSeek'] as bool? ?? false,
      showStop: value['showStop'] as bool? ?? true,
      keepPausedOnSkip: value['keepPausedOnSkip'] as bool? ?? true,
    );
  }
}
