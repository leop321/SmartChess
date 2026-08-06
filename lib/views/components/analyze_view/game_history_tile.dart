import 'package:flutter/material.dart';

import '../../../model/app_themes.dart';
import '../../../model/game_analysis_models.dart';

/// A compact, premium-styled list tile representing a single chess game.
/// Used in the Analyze hub, Player Insights, and Library views.
class GameHistoryTile extends StatelessWidget {
  final GameEntry game;
  final AppTheme theme;
  final VoidCallback? onTap;

  const GameHistoryTile({
    Key? key,
    required this.game,
    required this.theme,
    this.onTap,
  }) : super(key: key);

  // ─── Colour helpers ──────────────────────────────────────────────────────

  Color _resultColor() {
    switch (game.winner) {
      case 'white':
        return const Color(0xFF4CAF50);
      case 'black':
        return const Color(0xFFF44336);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  String _resultLabel(String username) {
    final isWhite = game.white.toLowerCase() == username.toLowerCase();
    if (game.winner == 'draw') return 'D';
    return (isWhite && game.winner == 'white') ||
            (!isWhite && game.winner == 'black')
        ? 'W'
        : 'L';
  }

  Color _platformColor() {
    switch (game.platform) {
      case GamePlatform.lichess:
        return const Color(0xFF8BAACF);
      case GamePlatform.chessCom:
        return const Color(0xFF6AAF6A);
      case GamePlatform.local:
        return const Color(0xFFB0A060);
    }
  }

  String _speedIcon() {
    switch (game.speed) {
      case 'bullet':
        return '⚡';
      case 'blitz':
        return '🔥';
      case 'rapid':
        return '⏱';
      case 'classical':
        return '⌛';
      default:
        return '♟';
    }
  }

  @override
  Widget build(BuildContext context) {
    final platColor = _platformColor();
    final resultColor = _resultColor();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              // ── Platform badge ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: platColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: platColor.withValues(alpha: 0.4),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  game.platform.displayName,
                  style: TextStyle(
                    color: platColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // ── Players ────────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${game.white} vs ${game.black}',
                      style: const TextStyle(
                        color: Color(0xFFE5E2E1),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          _speedIcon(),
                          style: const TextStyle(fontSize: 10),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          game.speed.isNotEmpty
                              ? game.speed[0].toUpperCase() +
                                  game.speed.substring(1)
                              : '—',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 11,
                            fontFamily: 'Inter',
                          ),
                        ),
                        if (game.whiteRating > 0 || game.blackRating > 0) ...[
                          Text(
                            '  •  ${game.whiteRating}–${game.blackRating}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 11,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // ── Result chip ─────────────────────────────────────────────
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: resultColor.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: resultColor.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _resultLabel(game.white), // show from white's perspective
                  style: TextStyle(
                    color: resultColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Inter',
                  ),
                ),
              ),

              // ── Chevron ────────────────────────────────────────────────
              if (onTap != null) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.25),
                  size: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
