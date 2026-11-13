import 'package:flutter/material.dart';

/// Icon controls for the expanded player; callbacks are supplied by the player.
class PlayerQuickActions extends StatelessWidget {
  const PlayerQuickActions({
    super.key,
    required this.sleepLabel,
    required this.sleepTooltip,
    required this.sleepActive,
    required this.speedLabel,
    required this.speedTooltip,
    required this.equalizerTooltip,
    required this.settingsTooltip,
    required this.onSleep,
    required this.onSpeed,
    required this.onEqualizer,
    required this.onSettings,
  });

  final String sleepLabel, sleepTooltip, speedLabel, speedTooltip;
  final String equalizerTooltip, settingsTooltip;
  final bool sleepActive;
  final VoidCallback onSleep, onSpeed, onEqualizer, onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget control({
      required Key key,
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
      String? status,
      bool active = false,
    }) => Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(
            key: key,
            tooltip: tooltip,
            onPressed: onPressed,
            style: active
                ? IconButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                  )
                : null,
            icon: Icon(icon),
          ),
          const SizedBox(height: 4),
          Text(
            status ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        control(
          key: const ValueKey('player-sleep'),
          icon: Icons.bedtime_outlined,
          tooltip: sleepTooltip,
          onPressed: onSleep,
          status: sleepLabel,
          active: sleepActive,
        ),
        control(
          key: const ValueKey('player-speed'),
          icon: Icons.speed_rounded,
          tooltip: speedTooltip,
          onPressed: onSpeed,
          status: speedLabel,
        ),
        control(
          key: const ValueKey('player-equalizer'),
          icon: Icons.equalizer_rounded,
          tooltip: equalizerTooltip,
          onPressed: onEqualizer,
        ),
        control(
          key: const ValueKey('player-settings'),
          icon: Icons.tune_rounded,
          tooltip: settingsTooltip,
          onPressed: onSettings,
        ),
      ],
    );
  }
}
