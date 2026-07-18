import 'package:chess/chess.dart' as dart_chess;

class ChessState {
  late dart_chess.Chess _chess;

  /// Creates a new chess game starting from the standard position,
  /// or from a specific FEN.
  ChessState({String? fen}) {
    if (fen != null) {
      _chess = dart_chess.Chess.fromFEN(fen);
    } else {
      _chess = dart_chess.Chess();
    }
  }

  /// Get the current position FEN.
  String get fen => _chess.fen;

  /// Get the current game history in PGN.
  String get pgn => _chess.pgn();

  /// Check if the game is over.
  bool get isGameOver => _chess.game_over;

  /// Check if the king is in checkmate.
  bool get isCheckmate => _chess.in_checkmate;

  /// Check if the game is drawn.
  bool get isDraw => _chess.in_draw;

  /// Check if the position is a stalemate.
  bool get isStalemate => _chess.in_stalemate;

  /// Check if there is a threefold repetition.
  bool get isThreefoldRepetition => _chess.in_threefold_repetition;

  /// Check if the current player is in check.
  bool get isInCheck => _chess.in_check;

  /// Get the list of all legal moves for the active side in standard SAN format.
  List<String> getLegalMovesSan() {
    return _chess.moves().map((m) => m.toString()).toList();
  }

  /// Executes a move and returns the SAN representation of the played move.
  /// If the move is invalid or illegal, returns null.
  /// The move can be in SAN (e.g. "e4", "Nf3") or a UCI string (e.g. "e2e4", "g1f3").
  String? makeMove(dynamic moveInput) {
    try {
      if (moveInput is String) {
        // Check if the move is in UCI format (e.g., "e2e4", "e7e8q")
        if (RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$').hasMatch(moveInput)) {
          final from = moveInput.substring(0, 2);
          final to = moveInput.substring(2, 4);
          final promotion =
              moveInput.length > 4 ? moveInput.substring(4, 5) : null;

          final moveMap = {
            'from': from,
            'to': to,
            if (promotion != null) 'promotion': promotion,
          };

          final success = _chess.move(moveMap);
          if (success) {
            final history = _chess.getHistory();
            if (history.isNotEmpty) {
              return history.last.toString();
            }
          }
        } else {
          // Treat as SAN (e.g., "Nf3", "e4")
          final success = _chess.move(moveInput);
          if (success) {
            final history = _chess.getHistory();
            if (history.isNotEmpty) {
              return history.last.toString();
            }
          }
        }
      } else if (moveInput is Map) {
        final success = _chess.move(moveInput);
        if (success) {
          final history = _chess.getHistory();
          if (history.isNotEmpty) {
            return history.last.toString();
          }
        }
      }
    } catch (e) {
      // Catch syntax errors or invalid moves
    }
    return null;
  }

  /// Undoes the last move and returns the SAN of the undone move.
  String? undoMove() {
    final history = _chess.getHistory();
    if (history.isEmpty) return null;
    final lastMoveSan = history.last.toString();
    final undone = _chess.undo();
    if (undone != null) {
      return lastMoveSan;
    }
    return null;
  }

  /// Resets the game to the starting position or a given FEN.
  void reset({String? fen}) {
    if (fen != null) {
      _chess = dart_chess.Chess.fromFEN(fen);
    } else {
      _chess = dart_chess.Chess();
    }
  }
}
