import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../logic/chess_piece.dart';
import '../../../logic/move_calculation/move_classes/move.dart';
import '../../../logic/puzzle/puzzle_session_state.dart';
import '../../../model/app_model.dart';
import '../../../model/app_themes.dart';
import '../../../model/player.dart';

/// Unicode-Schachsymbole pro Figurtyp und Spieler.
/// ♔♕♖♗♘♙ = Weiß (player1), ♚♛♜♝♞♟ = Schwarz (player2)
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

/// Ein leichtgewichtiges, Flame-freies Schachbrett für den Puzzle-Modus.
///
/// Rendert das Brett per CustomPainter mit den AppTheme-Farben.
/// Figuren werden als Unicode-Schachsymbole dargestellt – kein Asset-Loading,
/// kein async, vollständig isoliert vom normalen Spielmodus.
class PuzzleBoardWidget extends StatelessWidget {
  const PuzzleBoardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.select<AppModel, AppTheme>((m) => m.theme);
    final puzzleState = context.watch<PuzzleSessionState>();

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
          final tile = row * 8 + col;
          puzzleState.handleTap(tile);
        },
        child: CustomPaint(
          painter: _PuzzleBoardPainter(
            theme: theme,
            tiles: puzzleState.board.tiles,
            validMoves: puzzleState.validMovesForSelected,
            selectedPiece: puzzleState.selectedPiece,
            latestMove: puzzleState.latestMove,
            incorrectFromTile: puzzleState.incorrectFromTile,
            incorrectToTile: puzzleState.incorrectToTile,
          ),
        ),
      ),
    );
  }
}

class _PuzzleBoardPainter extends CustomPainter {
  final AppTheme theme;
  final List<ChessPiece?> tiles;
  final List<int> validMoves;
  final ChessPiece? selectedPiece;
  final Move? latestMove;
  final int? incorrectFromTile;
  final int? incorrectToTile;

  const _PuzzleBoardPainter({
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

        // Base tile color
        final isLight = (row + col) % 2 == 0;
        canvas.drawRect(rect, isLight ? lightPaint : darkPaint);

        // Latest move highlight
        if (latestMove != null &&
            (tile == latestMove!.from || tile == latestMove!.to)) {
          canvas.drawRect(rect, latestMovePaint);
        }

        // Selected piece highlight
        if (selectedPiece != null && tile == selectedPiece!.tile) {
          canvas.drawRect(rect, selectedPaint);
        }

        // Incorrect move highlight
        if (tile == incorrectFromTile || tile == incorrectToTile) {
          canvas.drawRect(rect, incorrectPaint);
        }

        // Valid move dots
        if (validMoves.contains(tile)) {
          final piece = tiles[tile];
          if (piece != null) {
            // Capture: ring around piece
            canvas.drawCircle(
              rect.center,
              tileSize * 0.46,
              Paint()
                ..color = theme.moveHint.withValues(alpha: 0.5)
                ..style = PaintingStyle.stroke
                ..strokeWidth = tileSize * 0.08,
            );
          } else {
            // Empty square: dot in center
            canvas.drawCircle(rect.center, tileSize * 0.16, hintPaint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PuzzleBoardPainter old) {
    return old.tiles != tiles ||
        old.validMoves != validMoves ||
        old.selectedPiece != selectedPiece ||
        old.latestMove != latestMove ||
        old.incorrectFromTile != incorrectFromTile ||
        old.incorrectToTile != incorrectToTile ||
        old.theme != theme;
  }
}

/// Overlay mit Figuren-Widgets (Unicode-Text), das über den Painter gelegt wird.
class PuzzlePiecesOverlay extends StatelessWidget {
  const PuzzlePiecesOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final puzzleState = context.watch<PuzzleSessionState>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileSize = constraints.maxWidth / 8;
        final pieces = <Widget>[];

        for (int i = 0; i < 64; i++) {
          final piece = puzzleState.board.tiles[i];
          if (piece == null) continue;

          final row = i ~/ 8;
          final col = i % 8;
          final symbol =
              _unicodePieces[piece.player]?[piece.type] ?? '?';

          // Drop shadow for contrast on both light and dark tiles
          final textColor = piece.player == Player.player1
              ? const Color(0xFFF5F0E8)
              : const Color(0xFF1A1A1A);
          final shadowColor = piece.player == Player.player1
              ? const Color(0xFF2A2A2A)
              : const Color(0xFFF5F0E8);

          pieces.add(
            Positioned(
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
            ),
          );
        }

        return Stack(children: pieces);
      },
    );
  }
}

/// Kombiniert Brett-Painter + Figuren-Overlay in einem einzigen Widget.
class PuzzleBoardWithPieces extends StatelessWidget {
  const PuzzleBoardWithPieces({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: const [
        PuzzleBoardWidget(),
        Positioned.fill(child: PuzzlePiecesOverlay()),
      ],
    );
  }
}
