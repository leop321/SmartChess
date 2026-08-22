
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/chess_piece.dart';
import '../logic/move_calculation/move_classes/move.dart';
import '../logic/puzzle/puzzle_session_state.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/player.dart';
import 'components/shared/glass_panel.dart';

// ── Shared DotGridPainter ──
class DotGridPainter extends CustomPainter {
  final Color color;
  const DotGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;
    const spacing = 20.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}



// ─────────────────────────────────────────────────────
// Main TacticsView
// ─────────────────────────────────────────────────────

class TacticsView extends StatelessWidget {
  const TacticsView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Selector<AppModel, AppTheme>(
      selector: (_, m) => m.theme,
      builder: (context, theme, _) {
        return Scaffold(
          body: Container(
            decoration: BoxDecoration(gradient: theme.background),
            child: Stack(
              children: [
                // 1. Dot Grid Background
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: DotGridPainter(
                        color: theme.lightTile.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                ),

                // 2. Ambient Glow Blob Top-Right
                Positioned(
                  top: 80,
                  right: -50,
                  child: RepaintBoundary(
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: theme.lightTile.withValues(alpha: 0.06),
                            blurRadius: 110,
                            spreadRadius: 25,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. Main Content
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        Text(
                          'TAKTIK',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: theme.lightTile.withValues(alpha: 0.6),
                            letterSpacing: 3.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Puzzles & Training',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFE5E2E1),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Expanded(child: _PuzzleSessionScreen()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────
// Puzzle Session Screen
// ─────────────────────────────────────────────────────

class _PuzzleSessionScreen extends StatefulWidget {
  const _PuzzleSessionScreen();

  @override
  State<_PuzzleSessionScreen> createState() => _PuzzleSessionScreenState();
}

class _PuzzleSessionScreenState extends State<_PuzzleSessionScreen> {
  late final PuzzleSessionState _runner;

  @override
  void initState() {
    super.initState();
    _runner = PuzzleSessionState();
    _runner.loadNextPuzzle();
  }

  @override
  void dispose() {
    _runner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PuzzleSessionState>.value(
      value: _runner,
      child: const _PuzzleSessionBody(),
    );
  }
}

class _PuzzleSessionBody extends StatelessWidget {
  const _PuzzleSessionBody();

  @override
  Widget build(BuildContext context) {
    final theme = context.select<AppModel, AppTheme>((m) => m.theme);

    return SingleChildScrollView(
      child: Column(
        children: [
          _StatusBanner(theme: theme),
          const SizedBox(height: 12),
          GlassPanel(
            padding: const EdgeInsets.all(4),
            borderRadius: 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _PuzzleBoardArea(),
            ),
          ),
          const SizedBox(height: 16),
          _RatingBadge(theme: theme),
          const SizedBox(height: 12),
          _NextPuzzleButton(theme: theme),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// Sub-Widgets
// ─────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final AppTheme theme;
  const _StatusBanner({required this.theme});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PuzzleSessionState>();
    final (label, color, icon) = switch (state.status) {
      PuzzleStatus.loading => (
          'Puzzle wird geladen …',
          theme.lightTile.withValues(alpha: 0.7),
          Icons.hourglass_empty_rounded,
        ),
      PuzzleStatus.showingOpponentMove => (
          'Gegner zieht …',
          theme.moveHint,
          Icons.arrow_forward_rounded,
        ),
      PuzzleStatus.waitingForPlayerMove => (
          'Dein Zug – finde den besten Zug!',
          theme.lightTile,
          Icons.psychology_rounded,
        ),
      PuzzleStatus.correct => (
          'Richtig! ✓',
          const Color(0xFF4CAF50),
          Icons.check_circle_rounded,
        ),
      PuzzleStatus.incorrect => (
          'Nicht korrekt – probiere es erneut',
          const Color(0xFFFF5555),
          Icons.close_rounded,
        ),
      PuzzleStatus.solved => (
          'Puzzle gelöst! 🎉',
          const Color(0xFF4CAF50),
          Icons.emoji_events_rounded,
        ),
      PuzzleStatus.errorNetwork => (
          'Netzwerkfehler. Bitte Verbindung prüfen.',
          const Color(0xFFFF5555),
          Icons.wifi_off_rounded,
        ),
      PuzzleStatus.errorServer => (
          'Server-Limit erreicht. Bitte kurz warten.',
          const Color(0xFFFF5555),
          Icons.dns_rounded,
        ),
      PuzzleStatus.errorParse => (
          'Puzzle-Format ungültig.',
          const Color(0xFFFF5555),
          Icons.error_outline_rounded,
        ),
      PuzzleStatus.error => (
          state.errorMessage ?? 'Fehler beim Laden',
          const Color(0xFFFF5555),
          Icons.error_outline_rounded,
        ),
    };

    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      borderRadius: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PuzzleBoardArea extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<PuzzleSessionState>();
    if (state.status == PuzzleStatus.loading) {
      final theme = context.select<AppModel, AppTheme>((m) => m.theme);
      return AspectRatio(
        aspectRatio: 1.0,
        child: Container(
          color: theme.darkTile,
          child: Center(
            child: CircularProgressIndicator(
              color: theme.lightTile,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }
    return _InlinePuzzleBoard();
  }
}

/// Inline-Brett, das auf dem PuzzleSessionState aufbaut.
/// Delegiert Tap-Events an runner.handleTap und rendert per CustomPainter.
class _InlinePuzzleBoard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final runner = context.watch<PuzzleSessionState>();
    final theme = context.select<AppModel, AppTheme>((m) => m.theme);

    return AspectRatio(
      aspectRatio: 1.0,
      child: GestureDetector(
        onTapUp: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final localPos = box.globalToLocal(details.globalPosition);
          final tileSize = box.size.width / 8;
          final col = (localPos.dx / tileSize).floor().clamp(0, 7);
          final row = (localPos.dy / tileSize).floor().clamp(0, 7);
          runner.handleTap(row * 8 + col);
        },
        child: Stack(
          children: [
            // Board painter
            Positioned.fill(
              child: CustomPaint(
                painter: _InlineBoardPainter(
                  theme: theme,
                  tiles: runner.board.tiles,
                  validMoves: runner.validMovesForSelected,
                  selectedPiece: runner.selectedPiece,
                  latestMove: runner.latestMove,
                  incorrectFromTile: runner.incorrectFromTile,
                  incorrectToTile: runner.incorrectToTile,
                ),
              ),
            ),
            // Pieces overlay
            Positioned.fill(
              child: _InlinePiecesOverlay(
                tiles: runner.board.tiles,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineBoardPainter extends CustomPainter {
  final AppTheme theme;
  final List<ChessPiece?> tiles;
  final List<int> validMoves;
  final ChessPiece? selectedPiece;
  final Move? latestMove;
  final int? incorrectFromTile;
  final int? incorrectToTile;

  const _InlineBoardPainter({
    required this.theme,
    required this.tiles,
    required this.validMoves,
    this.selectedPiece,
    this.latestMove,
    this.incorrectFromTile,
    this.incorrectToTile,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tileSize = size.width / 8;
    final lightPaint = Paint()..color = theme.lightTile;
    final darkPaint = Paint()..color = theme.darkTile;
    final hintPaint = Paint()..color = theme.moveHint.withValues(alpha: 0.45);
    final selectedPaint = Paint()
      ..color = theme.latestMove.withValues(alpha: 0.5);
    final latestMovePaint = Paint()
      ..color = theme.latestMove.withValues(alpha: 0.3);
    final incorrectPaint = Paint()
      ..color = const Color(0xCCFF4444).withValues(alpha: 0.55);

    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        final tile = row * 8 + col;
        final rect = Rect.fromLTWH(
            col * tileSize, row * tileSize, tileSize, tileSize);
        final isLight = (row + col) % 2 == 0;
        canvas.drawRect(rect, isLight ? lightPaint : darkPaint);

        if (latestMove != null &&
            (tile == latestMove!.from || tile == latestMove!.to)) {
          canvas.drawRect(rect, latestMovePaint);
        }
        if (selectedPiece != null && tile == selectedPiece!.tile) {
          canvas.drawRect(rect, selectedPaint);
        }
        if (tile == incorrectFromTile || tile == incorrectToTile) {
          canvas.drawRect(rect, incorrectPaint);
        }
        if (validMoves.contains(tile)) {
          final piece = tiles[tile];
          if (piece != null) {
            canvas.drawCircle(
              rect.center,
              tileSize * 0.46,
              Paint()
                ..color = theme.moveHint.withValues(alpha: 0.5)
                ..style = PaintingStyle.stroke
                ..strokeWidth = tileSize * 0.08,
            );
          } else {
            canvas.drawCircle(rect.center, tileSize * 0.16, hintPaint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _InlineBoardPainter old) => true;
}

const _unicodePieces = {
  Player.player1: {
    ChessPieceType.king: '♔',
    ChessPieceType.queen: '♕',
    ChessPieceType.rook: '♖',
    ChessPieceType.bishop: '♗',
    ChessPieceType.knight: '♘',
    ChessPieceType.pawn: '♙',
  },
  Player.player2: {
    ChessPieceType.king: '♚',
    ChessPieceType.queen: '♛',
    ChessPieceType.rook: '♜',
    ChessPieceType.bishop: '♝',
    ChessPieceType.knight: '♞',
    ChessPieceType.pawn: '♟',
  },
};

class _InlinePiecesOverlay extends StatelessWidget {
  final List<ChessPiece?> tiles;
  const _InlinePiecesOverlay({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final tileSize = constraints.maxWidth / 8;
      final pieces = <Widget>[];
      for (int i = 0; i < 64; i++) {
        final piece = tiles[i];
        if (piece == null) continue;
        final row = i ~/ 8;
        final col = i % 8;
        final symbol = _unicodePieces[piece.player]?[piece.type] ?? '?';
        final textColor = piece.player == Player.player1
            ? const Color(0xFFF5F0E8)
            : const Color(0xFF1A1A1A);
        final shadowColor = piece.player == Player.player1
            ? const Color(0xFF2A2A2A)
            : const Color(0xFFF5F0E8);
        pieces.add(Positioned(
          left: col * tileSize,
          top: row * tileSize,
          width: tileSize,
          height: tileSize,
          child: Center(
            child: Text(
              symbol,
              style: TextStyle(
                fontSize: tileSize * 0.72,
                color: textColor,
                shadows: [
                  Shadow(
                    color: shadowColor.withValues(alpha: 0.8),
                    blurRadius: 2,
                    offset: const Offset(0.5, 0.5),
                  ),
                ],
              ),
            ),
          ),
        ));
      }
      return Stack(children: pieces);
    });
  }
}

class _RatingBadge extends StatelessWidget {
  final AppTheme theme;
  const _RatingBadge({required this.theme});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PuzzleSessionState>();
    final puzzle = state.currentPuzzle;
    if (puzzle == null) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.bar_chart_rounded,
            size: 16, color: theme.lightTile.withValues(alpha: 0.6)),
        const SizedBox(width: 4),
        Text(
          'Rating: ${puzzle.rating}',
          style: TextStyle(
            fontSize: 13,
            color: theme.lightTile.withValues(alpha: 0.6),
            fontWeight: FontWeight.w500,
          ),
        ),
        if (puzzle.themes.isNotEmpty) ...[
          const SizedBox(width: 12),
          Icon(Icons.label_outline_rounded,
              size: 14, color: theme.lightTile.withValues(alpha: 0.4)),
          const SizedBox(width: 4),
          Text(
            puzzle.themes.take(2).join(', '),
            style: TextStyle(
              fontSize: 12,
              color: theme.lightTile.withValues(alpha: 0.4),
            ),
          ),
        ],
      ],
    );
  }
}

class _NextPuzzleButton extends StatelessWidget {
  final AppTheme theme;
  const _NextPuzzleButton({required this.theme});

  @override
  Widget build(BuildContext context) {
    final runner = context.watch<PuzzleSessionState>();
    final bool isError = runner.status == PuzzleStatus.errorNetwork ||
        runner.status == PuzzleStatus.errorServer ||
        runner.status == PuzzleStatus.errorParse ||
        runner.status == PuzzleStatus.error;

    if (runner.status != PuzzleStatus.solved && !isError) {
      return const SizedBox.shrink();
    }

    final label = isError ? 'Erneut versuchen' : 'Nächstes Puzzle';
    final icon = isError ? Icons.refresh_rounded : Icons.arrow_forward_rounded;

    return GestureDetector(
      onTap: runner.loadNextPuzzle,
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        borderRadius: 30,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFFE5E2E1)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFFE5E2E1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
