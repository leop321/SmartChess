import '../../../model/player.dart';
import '../../chess_piece.dart';
import 'move.dart';

class MoveMeta {
  Move? move;
  Player? player;
  ChessPieceType? type;
  bool took = false;
  bool kingCastle = false;
  bool queenCastle = false;
  bool promotion = false;
  ChessPieceType? promotionType;
  bool isCheck = false;
  bool isCheckmate = false;
  bool isStalemate = false;
  bool rowIsAmbiguous = false;
  bool colIsAmbiguous = false;

  MoveMeta(this.move, this.player, this.type);

  /// Returns a human-readable long-form description of this move,
  /// e.g. "Rook takes D4", "Castle King-side", "Queen H7 (Promotion to Queen)".
  String toLongString() {
    if (kingCastle) return 'Castle King-side';
    if (queenCastle) return 'Castle Queen-side';

    final col = move?.to != null ? move!.to % 8 : 0;
    final row = move?.to != null ? (move!.to ~/ 8) : 0;
    final f = String.fromCharCode('a'.codeUnitAt(0) + col).toUpperCase();
    final r = (8 - row).toString();
    final toSq = '$f$r';

    String pieceName = _pieceName(type);
    String captureWord = took ? ' takes' : '';
    String promoSuffix = '';
    if (promotion && promotionType != null) {
      promoSuffix = ' (Promotion to ${_pieceName(promotionType)})';
    }

    if (pieceName.isEmpty) {
      // Pawn
      if (took) {
        final fromCol = move?.from != null ? move!.from % 8 : 0;
        final fromF = String.fromCharCode('a'.codeUnitAt(0) + fromCol);
        return '$fromF takes $toSq$promoSuffix'.trim();
      }
      return '$toSq$promoSuffix'.trim();
    }
    return '$pieceName$captureWord $toSq$promoSuffix'.trim();
  }

  static String _pieceName(ChessPieceType? t) {
    switch (t) {
      case ChessPieceType.king:
        return 'King';
      case ChessPieceType.queen:
        return 'Queen';
      case ChessPieceType.rook:
        return 'Rook';
      case ChessPieceType.bishop:
        return 'Bishop';
      case ChessPieceType.knight:
        return 'Knight';
      case ChessPieceType.pawn:
        return '';
      default:
        return '';
    }
  }
}
