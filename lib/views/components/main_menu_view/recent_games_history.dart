import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../logic/game_history_storage.dart';
import '../../../../model/app_model.dart';
import '../../../../model/completed_game.dart';
import '../../../../model/player.dart';
import '../../chess_view.dart';
import '../shared/glass_panel.dart';

class RecentGamesHistory extends StatefulWidget {
  const RecentGamesHistory({Key? key}) : super(key: key);

  @override
  _RecentGamesHistoryState createState() => _RecentGamesHistoryState();
}

class _RecentGamesHistoryState extends State<RecentGamesHistory> {
  List<CompletedGame>? _history;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() async {
    final history = await GameHistoryStorage.loadGameHistory();
    if (mounted) {
      setState(() {
        _history = history;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_history == null) {
      return const Center(child: CupertinoActivityIndicator());
    }

    if (_history!.isEmpty) {
      return const SizedBox.shrink(); // Hide if no history
    }

    final appModel = Provider.of<AppModel>(context, listen: false);
    final theme = appModel.theme;

    final isDark = ThemeData.estimateBrightnessForColor(
            theme.background?.colors.first ?? Colors.black) ==
        Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF241A00);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8, top: 16),
          child: Text(
            'RECENT GAMES',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: textColor.withValues(alpha: 0.6),
            ),
          ),
        ),
        ..._history!.map((game) {
          final isAI = game.playerCount == 1;
          String title = isAI
              ? 'vs AI (${AppModel.getDifficultyElo(game.aiDifficulty)} ELO)'
              : '2 Player Match';

          String outcome;
          Color outcomeColor;
          if (game.stalemate) {
            outcome = 'DRAW';
            outcomeColor = const Color(0xFFB0BEC5);
          } else if (isAI) {
            if (game.winner == game.playerSide) {
              outcome = 'WIN';
              outcomeColor = const Color(0xFF81C784);
            } else {
              outcome = 'LOSS';
              outcomeColor = const Color(0xFFE57373);
            }
          } else {
            outcome = game.winner == Player.player1 ? 'WHITE WON' : 'BLACK WON';
            outcomeColor = textColor;
          }

          final monthNames = [
            'Jan',
            'Feb',
            'Mar',
            'Apr',
            'May',
            'Jun',
            'Jul',
            'Aug',
            'Sep',
            'Oct',
            'Nov',
            'Dec'
          ];
          final dateStr =
              '${monthNames[game.date.month - 1]} ${game.date.day}, ${game.date.year} ${game.date.hour.toString().padLeft(2, '0')}:${game.date.minute.toString().padLeft(2, '0')}';

          final numMoves = (game.moves.length / 2).ceil();

          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                appModel.haptic.light();
                appModel.loadCompletedGame(game);
                Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (context) => ChessView(appModel, isResuming: true),
                  ),
                ).then((_) => _loadHistory());
              },
              child: GlassPanel(
                borderRadius: 16,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: outcomeColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        game.stalemate
                            ? CupertinoIcons.minus_circle_fill
                            : (outcome == 'WIN' || game.winner == Player.player1
                                ? CupertinoIcons.check_mark_circled_solid
                                : CupertinoIcons.xmark_circle_fill),
                        color: outcomeColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$dateStr • $numMoves moves',
                            style: TextStyle(
                              fontSize: 12,
                              color: textColor.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      color: textColor.withValues(alpha: 0.3),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }
}
