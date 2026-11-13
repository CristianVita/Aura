import 'package:flutter/material.dart';

import 'app_strings.dart';

/// Uses the same playback action for the mini and expanded players.
class PlayerSkipButton extends StatelessWidget {
  const PlayerSkipButton({
    super.key,
    required this.next,
    required this.enabled,
    required this.onSkip,
    this.iconSize = 24,
    this.color,
  });

  final bool next;
  final bool enabled;
  final Future<void> Function(bool next) onSkip;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: next
        ? context.appStrings.uiNextTrack
        : context.appStrings.uiPreviousTrack,
    onPressed: enabled ? () => onSkip(next) : null,
    icon: Icon(
      next ? Icons.skip_next_rounded : Icons.skip_previous_rounded,
      size: iconSize,
      color: color,
    ),
  );
}
