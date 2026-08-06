import 'package:chess/chess.dart' as ch;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../logic/shared_functions.dart';
import '../../../model/app_themes.dart';

/// A lightweight, interactive chess board for tactics puzzles.
///
/// Renders squares, pieces (via Image.asset), and overlays
/// (last-move highlight, selected square, valid-move dots, check flash,
/// hint glow, wrong-move flash).
class TacticsBoardWidget extends StatelessWidget {
  final AppTheme theme;
  final String pieceTheme;
  final String fen;
  final int? selectedTile;
  final List<int> validDestinations;
  final String? lastMovePair; // UCI e.g. "e2e4"
  final int? hintTile;
  final bool showWrongFlash;
  final bool showCorrectFlash;
  final bool isFlipped; // true if player is black

  final void Function(int tile) onTileTap;

  const TacticsBoardWidget({
    Key? key,
    required this.theme,
    required this.pieceTheme,
    required this.fen,
    required this.onTileTap,
    this.selectedTile,
    this.validDestinations = const [],
    this.lastMovePair,
    this.hintTile,
    this.showWrongFlash = false,
    this.showCorrectFlash = false,
    this.isFlipped = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final board = ch.Chess.fromFEN(fen);

    // Parse last move highlight squares
    int? lastFrom, lastTo;
    if (lastMovePair != null && lastMovePair!.length >= 4) {
      lastFrom = _algebraicToTile(lastMovePair!.substring(0, 2));
      lastTo = _algebraicToTile(lastMovePair!.substring(2, 4));
    }

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileSize = constraints.maxWidth / 8;
          return Stack(
            children: [
              // ── Board grid ────────────────────────────────────────────────
              GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8),
                itemCount: 64,
                itemBuilder: (context, visualIndex) {
                  final tile = isFlipped ? 63 - visualIndex : visualIndex;
                  final file = tile % 8;
                  final rank = tile ~/ 8;
                  final isLight = (file + rank) % 2 == 0;
                  final sq = _tileToAlgebraic(tile);
                  final piece = board.get(sq);

                  // Overlay logic
                  final isSelected = selectedTile == tile;
                  final isValidDest = validDestinations.contains(tile);
                  final isLastFrom = lastFrom == tile;
                  final isLastTo = lastTo == tile;
                  final isHint = hintTile == tile;

                  // Check highlight
                  final isKingInCheck = _isKingInCheck(board, tile);

                  // Base square color
                  Color squareColor =
                      isLight ? theme.lightTile : theme.darkTile;

                  // Last move tint
                  if (isLastFrom || isLastTo) {
                    squareColor =
                        Color.lerp(squareColor, theme.latestMove, 0.45)!;
                  }

                  // Selection tint
                  if (isSelected) {
                    squareColor =
                        Color.lerp(squareColor, theme.moveHint, 0.45)!;
                  }

                  // Check tint
                  if (isKingInCheck) {
                    squareColor =
                        Color.lerp(squareColor, const Color(0xFFFF3333), 0.5)!;
                  }

                  // Wrong flash
                  if (showWrongFlash && isSelected) {
                    squareColor =
                        Color.lerp(squareColor, const Color(0xFFFF3333), 0.5)!;
                  }
                  // Correct flash
                  if (showCorrectFlash && (isLastFrom || isLastTo)) {
                    squareColor =
                        Color.lerp(squareColor, const Color(0xFF4CAF50), 0.4)!;
                  }

                  return GestureDetector(
                    onTap: () => onTileTap(tile),
                    child: Container(
                      color: squareColor,
                      child: Stack(
                        children: [
                          // Hint pulse glow
                          if (isHint)
                            Positioned.fill(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 600),
                                decoration: BoxDecoration(
                                  color: theme.moveHint.withValues(alpha: 0.35),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          theme.moveHint.withValues(alpha: 0.6),
                                      blurRadius: tileSize * 0.5,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // Valid move dot or capture ring
                          if (isValidDest)
                            Center(
                              child: piece == null
                                  ? Container(
                                      width: tileSize * 0.30,
                                      height: tileSize * 0.30,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: theme.moveHint
                                            .withValues(alpha: 0.55),
                                      ),
                                    )
                                  : Container(
                                      width: tileSize * 0.90,
                                      height: tileSize * 0.90,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: theme.moveHint
                                              .withValues(alpha: 0.60),
                                          width: tileSize * 0.08,
                                        ),
                                      ),
                                    ),
                            ),

                          // Piece image
                          if (piece != null)
                            Padding(
                              padding: EdgeInsets.all(tileSize * 0.04),
                              child: Image.asset(
                                _pieceAssetPath(piece, pieceTheme),
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const SizedBox(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  bool _isKingInCheck(ch.Chess board, int tile) {
    final sq = _tileToAlgebraic(tile);
    final piece = board.get(sq);
    if (piece == null || piece.type != ch.PieceType.KING) return false;
    return board.in_check;
  }

  static String _tileToAlgebraic(int tile) {
    final file = tile % 8;
    final rank = tile ~/ 8;
    return '${String.fromCharCode(97 + file)}${8 - rank}';
  }

  static int _algebraicToTile(String sq) {
    final file = sq.codeUnitAt(0) - 97;
    final rank = 8 - int.parse(sq[1]);
    return rank * 8 + file;
  }

  static String _pieceAssetPath(ch.Piece piece, String pieceTheme) {
    final color = piece.color == ch.Color.WHITE ? 'white' : 'black';
    final type = _pieceTypeName(piece.type);
    final folder = formatPieceTheme(pieceTheme);
    return 'assets/images/pieces/$folder/${type}_$color.png';
  }

  static String _pieceTypeName(ch.PieceType type) {
    switch (type) {
      case ch.PieceType.PAWN:
        return 'pawn';
      case ch.PieceType.ROOK:
        return 'rook';
      case ch.PieceType.KNIGHT:
        return 'knight';
      case ch.PieceType.BISHOP:
        return 'bishop';
      case ch.PieceType.QUEEN:
        return 'queen';
      case ch.PieceType.KING:
        return 'king';
      default:
        return 'pawn';
    }
  }
}
