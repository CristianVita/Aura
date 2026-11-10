class MusicBrainzGate {
  Future<void> _pending = Future.value();
  DateTime? _lastRequest;

  Future<T> run<T>(Future<T> Function() request, Duration interval) {
    final result = _pending.then((_) async {
      final previous = _lastRequest;
      if (previous != null) {
        final elapsed = DateTime.now().difference(previous);
        final delay = elapsed.isNegative ? interval : interval - elapsed;
        if (delay > Duration.zero) await Future<void>.delayed(delay);
      }
      _lastRequest = DateTime.now();
      return request();
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

final musicBrainzGate = MusicBrainzGate();
