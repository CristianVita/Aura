import 'dart:async';

import 'package:flutter/foundation.dart';

/// Deadline based, so a delayed tick never extends the chosen sleep period.
class SleepTimerController extends ChangeNotifier {
  SleepTimerController({
    required this.pause,
    required this.isPlaying,
    required this.onError,
    DateTime Function()? now,
    this._automaticTicks = true,
  }) : _now = now ?? DateTime.now;
  final Future<void> Function() pause;
  final bool Function() isPlaying;
  final VoidCallback onError;
  final DateTime Function() _now;
  final bool _automaticTicks;
  Timer? _ticker;
  DateTime? _deadline;
  bool _finishTrack = false;
  bool _waiting = false;
  bool _disposed = false;
  bool get active => _deadline != null || _waiting;
  bool get waitingForTrack => _waiting;
  Duration get remaining {
    final value = _deadline?.difference(_now()) ?? Duration.zero;
    return value.isNegative ? Duration.zero : value;
  }

  void start(Duration duration, {bool finishTrack = false}) {
    if (duration <= Duration.zero) throw ArgumentError.value(duration);
    cancel();
    _deadline = _now().add(duration);
    _finishTrack = finishTrack;
    _startTicker();
    notifyListeners();
  }

  void stopAfterTrack() {
    cancel();
    _waiting = true;
    notifyListeners();
  }

  void _startTicker() {
    if (_automaticTicks) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => checkDeadline(),
      );
    }
  }

  void checkDeadline() {
    if (_disposed || !active) return;
    if (_deadline != null && !_now().isBefore(_deadline!)) {
      _deadline = null;
      _ticker?.cancel();
      if (_finishTrack && isPlaying()) {
        _waiting = true;
      } else {
        _stop();
        return;
      }
    }
    notifyListeners();
  }

  void onTrackEnded() {
    // Handle a boundary arriving before a delayed deadline tick.
    checkDeadline();
    if (_waiting) _stop();
  }

  void _stop() {
    cancel();
    unawaited(
      pause().catchError((Object _) {
        if (!_disposed) onError();
      }),
    );
  }

  void cancel() {
    _ticker?.cancel();
    _ticker = null;
    _deadline = null;
    _waiting = false;
    _finishTrack = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    super.dispose();
  }
}
