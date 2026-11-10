import 'package:flutter/foundation.dart';

enum DiagnosticEventCode { playbackMemoryError, playbackSettingsError }

class DiagnosticEvent {
  const DiagnosticEvent(this.at, this.code);
  final DateTime at;
  final DiagnosticEventCode code;
  Map<String, String> toJson() => {
    'time': at.toUtc().toIso8601String(),
    'code': code.name,
  };
}

class DiagnosticJournal extends ChangeNotifier {
  static const maxEvents = 200;
  final List<DiagnosticEvent> _events = [];
  bool _active = false;
  bool get active => _active;
  List<DiagnosticEvent> get events => List.unmodifiable(_events);
  void start() {
    _events.clear();
    _active = true;
    notifyListeners();
  }

  void stop() {
    _active = false;
    notifyListeners();
  }

  void record(DiagnosticEventCode code) {
    if (!_active) return;
    if (_events.length == maxEvents) _events.removeAt(0);
    _events.add(DiagnosticEvent(DateTime.now(), code));
    notifyListeners();
  }
}

final diagnosticJournal = DiagnosticJournal();
