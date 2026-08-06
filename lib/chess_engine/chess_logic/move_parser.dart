import '../../../logic/chess_board.dart';
import '../../../logic/chess_piece.dart';
import '../../../logic/move_calculation/move_classes/move.dart';
import '../../../model/player.dart';

class MoveParser {
  /// Parses a chess move in Standard Algebraic Notation (SAN)
  /// and returns a list of phonetic tokens (e.g. ['knight', 'takes', 'd', '4']).
  ///
  /// The tokens returned are lowercase and correspond to pre-recorded assets:
  /// - Pieces: 'king', 'queen', 'rook', 'bishop', 'knight', 'pawn'
  /// - Letters: 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'
  /// - Numbers: '1', '2', '3', '4', '5', '6', '7', '8'
  /// - Actions: 'takes', 'castle', 'long_castle'
  static List<String> parseSan(String san) {
    // 1. Castling
    if (san == 'O-O' || san == '0-0') {
      return ['castle'];
    }
    if (san == 'O-O-O' || san == '0-0-0') {
      return ['long_castle'];
    }

    // Clean check (+), checkmate (#), and annotations (?, !, etc.)
    final cleanSan = san.replaceAll(RegExp(r'[+#?!]'), '');

    final List<String> tokens = [];

    // Parse piece name
    String remaining = cleanSan;
    String? piece;
    if (cleanSan.startsWith('K')) {
      piece = 'king';
      remaining = cleanSan.substring(1);
    } else if (cleanSan.startsWith('Q')) {
      piece = 'queen';
      remaining = cleanSan.substring(1);
    } else if (cleanSan.startsWith('R')) {
      piece = 'rook';
      remaining = cleanSan.substring(1);
    } else if (cleanSan.startsWith('B')) {
      piece = 'bishop';
      remaining = cleanSan.substring(1);
    } else if (cleanSan.startsWith('N')) {
      piece = 'knight';
      remaining = cleanSan.substring(1);
    }

    // Check if it's a capture
    final isCapture = remaining.contains('x');

    if (piece != null) {
      tokens.add(piece);
    }

    // If it's a pawn capture (e.g. exd5), the first char is the moving pawn's file
    if (piece == null && isCapture) {
      final parts = remaining.split('x');
      if (parts.isNotEmpty) {
        final pawnFile = parts[0];
        if (pawnFile.length == 1 && RegExp(r'[a-h]').hasMatch(pawnFile)) {
          tokens.add(pawnFile.toLowerCase());
        }
      }
    }

    if (isCapture) {
      tokens.add('takes');
      // Focus on the part after 'x'
      remaining = remaining.substring(remaining.indexOf('x') + 1);
    }

    // Find destination square (file and rank, e.g. "d4")
    final match = RegExp(r'([a-h])([1-8])').firstMatch(remaining);
    if (match != null) {
      final file = match.group(1)!;
      final rank = match.group(2)!;
      tokens.add(file.toLowerCase());
      tokens.add(rank);
    }

    // Handle pawn promotion (e.g. e8=Q)
    if (cleanSan.contains('=')) {
      final parts = cleanSan.split('=');
      if (parts.length > 1) {
        final promoPart = parts[1];
        if (promoPart.startsWith('Q')) {
          tokens.add('queen');
        } else if (promoPart.startsWith('R')) {
          tokens.add('rook');
        } else if (promoPart.startsWith('B')) {
          tokens.add('bishop');
        } else if (promoPart.startsWith('N')) {
          tokens.add('knight');
        }
      }
    }

    return tokens;
  }

  /// Converts a board square string (e.g. "e2") to a tile index (0 to 63)
  static int? coordinateToTile(String sq) {
    if (sq.length != 2) return null;
    final file = sq[0].toLowerCase().codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = int.tryParse(sq[1]);
    if (file < 0 || file > 7 || rank == null || rank < 1 || rank > 8) {
      return null;
    }
    // Row 0 is Rank 8, Row 7 is Rank 1
    final row = 8 - rank;
    return row * 8 + file;
  }

  /// Parses a coordinate move like "e2e4" or "g1f3" and returns a [Move] object.
  static Move? parseCoordinateMove(String moveStr) {
    final cleanStr =
        moveStr.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
    if (cleanStr.length < 4 || cleanStr.length > 5) return null;

    final fromTile = coordinateToTile(cleanStr.substring(0, 2));
    final toTile = coordinateToTile(cleanStr.substring(2, 4));
    if (fromTile == null || toTile == null) return null;

    return Move(fromTile, toTile);
  }

  /// Parses a chess move in Standard Algebraic Notation (SAN) like "Nf3", "e4", "O-O"
  /// and returns a concrete [Move] by validating legal moves on the given [board].
  static Move? parseSanMove(String san, ChessBoard board, Player turn) {
    final cleanSan = san.replaceAll(RegExp(r'[+#?!]'), '');

    // 1. Castling
    if (cleanSan == 'O-O' || cleanSan == '0-0') {
      final kingTile = turn == Player.player1 ? 60 : 4;
      final targetTile = turn == Player.player1 ? 62 : 6;
      return Move(kingTile, targetTile);
    }
    if (cleanSan == 'O-O-O' || cleanSan == '0-0-0') {
      final kingTile = turn == Player.player1 ? 60 : 4;
      final targetTile = turn == Player.player1 ? 58 : 2;
      return Move(kingTile, targetTile);
    }

    // 2. Extract destination square
    final match = RegExp(r'([a-h])([1-8])').firstMatch(cleanSan);
    if (match == null) return null;
    final destSquare = match.group(0)!;
    final destTile = coordinateToTile(destSquare);
    if (destTile == null) return null;

    // 3. Extract piece type
    ChessPieceType pieceType = ChessPieceType.pawn;
    if (cleanSan.startsWith('K')) {
      pieceType = ChessPieceType.king;
    } else if (cleanSan.startsWith('Q')) {
      pieceType = ChessPieceType.queen;
    } else if (cleanSan.startsWith('R')) {
      pieceType = ChessPieceType.rook;
    } else if (cleanSan.startsWith('B')) {
      pieceType = ChessPieceType.bishop;
    } else if (cleanSan.startsWith('N')) {
      pieceType = ChessPieceType.knight;
    }

    // 4. Extract disambiguation (e.g. 'b' in Nbd2 or '1' in R1e2)
    String disambig = '';
    final firstChar = cleanSan[0];
    final startsWithPiece = RegExp(r'[KQRBN]').hasMatch(firstChar);
    final startIdx = startsWithPiece ? 1 : 0;
    final endIdx = cleanSan.indexOf(destSquare);
    if (endIdx > startIdx) {
      disambig = cleanSan.substring(startIdx, endIdx).replaceAll('x', '');
    }

    // 5. Query matching candidates
    final friendlyPieces =
        turn == Player.player1 ? board.player1Pieces : board.player2Pieces;
    final List<ChessPiece> candidates = [];

    for (var piece in friendlyPieces) {
      if (piece.type != pieceType) continue;

      final legalMoves = board.movesForPiece(piece);
      if (legalMoves.contains(destTile)) {
        if (disambig.isNotEmpty) {
          final col = piece.tile % 8;
          final row = (piece.tile / 8).floor();
          final fileStr = String.fromCharCode('a'.codeUnitAt(0) + col);
          final rankStr = (8 - row).toString();

          if (disambig.length == 1) {
            if (disambig != fileStr && disambig != rankStr) continue;
          } else if (disambig.length == 2) {
            if (disambig != '$fileStr$rankStr') continue;
          }
        }
        candidates.add(piece);
      }
    }

    if (candidates.length == 1) {
      return Move(candidates.first.tile, destTile);
    }

    // Try fallback: check coordinate input directly (e.g. if the user typed "e2e4" as SAN)
    final directCoordMove = parseCoordinateMove(cleanSan);
    if (directCoordMove != null) {
      final piece = board.tiles[directCoordMove.from];
      if (piece != null && piece.player == turn && piece.type == pieceType) {
        final legalMoves = board.movesForPiece(piece);
        if (legalMoves.contains(directCoordMove.to)) {
          return directCoordMove;
        }
      }
    }

    return null;
  }
}
