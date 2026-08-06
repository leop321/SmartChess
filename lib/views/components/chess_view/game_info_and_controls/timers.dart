import 'package:flutter/material.dart';

import '../../../../model/app_model.dart';
import '../../../../model/player.dart';
import 'timer_widget.dart';

class Timers extends StatelessWidget {
  final AppModel appModel;

  Timers(this.appModel);

  @override
  Widget build(BuildContext context) {
    final theme = appModel.theme;
    final turn = appModel.turn;

    // Check active states
    final isP1Active = turn == Player.player1;
    final isP2Active = turn == Player.player2;

    // Label logic (P1 is White, P2 is Black)
    final aiEngineName = appModel.aiEngine == 'maya' ? 'MAYA' : 'STOCKFISH';
    final p1Label = appModel.playingWithAI
        ? (appModel.playerSide == Player.player1 ? 'YOU' : aiEngineName)
        : 'WHITE';
    final p2Label = appModel.playingWithAI
        ? (appModel.playerSide == Player.player2 ? 'YOU' : aiEngineName)
        : 'BLACK';

    if (appModel.timeLimit == 0) {
      if (!appModel.playingWithAI) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.only(bottom: 14.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.smart_toy_rounded,
                size: 16, color: theme.lightTile.withValues(alpha: 0.5)),
            const SizedBox(width: 6),
            Text(
              'PLAYING $aiEngineName',
              style: TextStyle(
                color: theme.lightTile.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            TimerWidget(
              timeLeft: appModel.player1TimeLeft,
              delayLeft: appModel.timerService.player1DelayLeft,
              isActive: isP1Active,
              label: p1Label,
              theme: theme,
            ),
            const SizedBox(width: 12),
            TimerWidget(
              timeLeft: appModel.player2TimeLeft,
              delayLeft: appModel.timerService.player2DelayLeft,
              isActive: isP2Active,
              label: p2Label,
              theme: theme,
            ),
          ],
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}
