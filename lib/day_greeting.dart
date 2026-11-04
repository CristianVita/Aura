import 'app_strings.dart';

import 'dart:async';

import 'package:flutter/material.dart';

class DayGreeting extends StatefulWidget {
  const DayGreeting({super.key, this.style});

  final TextStyle? style;

  @override
  State<DayGreeting> createState() => _DayGreetingState();
}

class _DayGreetingState extends State<DayGreeting> with WidgetsBindingObserver {
  Timer? _timer;
  late int _hour;

  String _currentGreeting(BuildContext context) {
    final hour = _hour;
    if (hour < 5) return context.appStrings.uiHelloNightOwl;
    if (hour >= 5 && hour < 12) return context.appStrings.uiGoodMorning;
    if (hour >= 12 && hour < 18) return context.appStrings.uiGoodAfternoon;
    return context.appStrings.uiGoodEvening;
  }

  @override
  void initState() {
    super.initState();
    _hour = DateTime.now().hour;
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _refresh() {
    final hour = DateTime.now().hour;
    if (hour != _hour) setState(() => _hour = hour);
  }

  void _startTimer() {
    _timer?.cancel();
    // Recheck the device clock even if its time or timezone was changed.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _startTimer();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text(_currentGreeting(context), style: widget.style);
}
