import 'dart:async';

import 'package:flutter/material.dart';

/// Large time + date, ticking on the minute.
class Clock extends StatefulWidget {
  const Clock({super.key});

  @override
  State<Clock> createState() => _ClockState();
}

class _ClockState extends State<Clock> {
  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  void _scheduleTick() {
    final now = DateTime.now();
    final nextMinute = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    _timer = Timer(nextMinute.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleTick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(_now);
    final timeText = MaterialLocalizations.of(context)
        .formatTimeOfDay(time, alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));
    final dateText = '${_weekdays[_now.weekday - 1]}, ${_now.day} ${_months[_now.month - 1]}';
    const shadow = [Shadow(blurRadius: 8, color: Colors.black45)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          timeText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 64,
            fontWeight: FontWeight.w300,
            shadows: shadow,
          ),
        ),
        Text(
          dateText,
          style: const TextStyle(color: Colors.white70, fontSize: 18, shadows: shadow),
        ),
      ],
    );
  }
}
