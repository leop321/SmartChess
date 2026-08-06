import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../logic/chess_piece.dart';
import '../../../../model/app_model.dart';
import '../../../../model/game_analysis_models.dart';
import '../analyze_view/game_analysis_page.dart';
import '../shared/glass_panel.dart';

class GameOverOverlay extends StatelessWidget {
  final AppModel appModel;
  final VoidCallback onReviewGame;

  const GameOverOverlay(
      {Key? key, required this.appModel, required this.onReviewGame})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Evaluate the game outcome
    String title = 'GAME OVER';
    Color titleColor = Colors.white;
    String subtitle = 'The game has ended.';

    if (appModel.stalemate) {
      title = 'STALEMATE';
      titleColor = const Color(0xFFB0BEC5);
      subtitle = 'The game is a draw.';
    } else if (appModel.playerCount == 1) {
      if (appModel.userWon) {
        title = 'YOU WIN!';
        titleColor = const Color(0xFF81C784); // Green
        subtitle = 'Congratulations on your victory!';
      } else {
        title = 'YOU LOSE';
        titleColor = const Color(0xFFE57373); // Red
        subtitle = 'Better luck next time.';
      }
    } else {
      title = appModel.userWon ? 'WHITE WINS!' : 'BLACK WINS!';
      titleColor = Colors.white;
      subtitle = 'Checkmate!';
    }

    return Positioned.fill(
      child: GestureDetector(
        onTap: () {}, // Prevent taps from passing through
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black.withValues(alpha: 0.3),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: GlassPanel(
                  borderRadius: 24,
                  color: const Color(0x90201F1F),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 12),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.5,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Analysis Button
                        _buildButton(
                          icon: CupertinoIcons.search,
                          label: 'Analysis',
                          color: const Color(0xFF64B5F6),
                          isPrimary: true,
                          onPressed: () {
                            appModel.haptic.light();
                            final movesList = appModel.moveMetaList
                                .map((meta) {
                                  if (meta.move == null) return '';
                                  final move = meta.move!;
                                  final fromFile = move.from % 8;
                                  final fromRank = 8 - (move.from ~/ 8);
                                  final toFile = move.to % 8;
                                  final toRank = 8 - (move.to ~/ 8);
                                  final fromStr =
                                      '${String.fromCharCode(97 + fromFile)}$fromRank';
                                  final toStr =
                                      '${String.fromCharCode(97 + toFile)}$toRank';
                                  String promo = '';
                                  if (meta.promotion &&
                                      meta.promotionType != null) {
                                    switch (meta.promotionType) {
                                      case ChessPieceType.queen:
                                        promo = 'q';
                                        break;
                                      case ChessPieceType.rook:
                                        promo = 'r';
                                        break;
                                      case ChessPieceType.bishop:
                                        promo = 'b';
                                        break;
                                      case ChessPieceType.knight:
                                        promo = 'n';
                                        break;
                                      default:
                                        break;
                                    }
                                  }
                                  return '$fromStr$toStr$promo';
                                })
                                .where((s) => s.isNotEmpty)
                                .join(' ');

                            final gameEntry = GameEntry(
                              platform: GamePlatform.local,
                              white:
                                  appModel.playerCount == 1 ? 'You' : 'White',
                              black: appModel.playerCount == 1 ? 'AI' : 'Black',
                              winner: appModel.stalemate
                                  ? 'draw'
                                  : (appModel.userWon ? 'white' : 'black'),
                              speed: 'local',
                              pgn: '',
                              moves: movesList,
                            );

                            Navigator.of(context).push(
                              CupertinoPageRoute(
                                builder: (_) =>
                                    GameAnalysisPage(game: gameEntry),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),

                        // Review Game Button
                        _buildButton(
                          icon: CupertinoIcons.play_circle,
                          label: 'Review Game',
                          color: const Color(0xFFE5E2E1),
                          isPrimary: false,
                          onPressed: () {
                            appModel.haptic.light();
                            appModel.setHistoryViewIndex(
                                appModel.moveMetaList.length > 0
                                    ? appModel.moveMetaList.length - 1
                                    : 0);
                            onReviewGame();
                          },
                        ),
                        const SizedBox(height: 12),

                        // Main Menu Button
                        _buildButton(
                          icon: CupertinoIcons.home,
                          label: 'Main Menu',
                          color: const Color(0xFFE5E2E1),
                          isPrimary: false,
                          onPressed: () {
                            appModel.haptic.light();
                            appModel.exitChessView();
                            Navigator.of(context).pop();
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool isPrimary,
    required VoidCallback onPressed,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        width: double.infinity,
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isPrimary ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPrimary
                ? color.withValues(alpha: 0.5)
                : color.withValues(alpha: 0.2),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: isPrimary ? FontWeight.w700 : FontWeight.w600,
                fontSize: 15,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
