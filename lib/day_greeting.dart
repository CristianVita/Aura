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
  late String _greeting;

  String _currentGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Bună dimineața';
    if (hour >= 12 && hour < 18) return 'Bună ziua';
    return 'Bună seara';
  }

  @override
  void initState() {
    super.initState();
    _greeting = _currentGreeting();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _refresh() {
    final greeting = _currentGreeting();
    if (greeting != _greeting) setState(() => _greeting = greeting);
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
  Widget build(BuildContext context) => Text(_greeting, style: widget.style);
}
