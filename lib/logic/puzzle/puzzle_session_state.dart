import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../logic/chess_board.dart';
import '../../logic/chess_piece.dart';
import '../../logic/move_calculation/move_classes/move.dart';
import '../../logic/puzzle/uci_move_converter.dart';
import '../../model/player.dart';
import '../../model/puzzle.dart';
import 'lichess_puzzle_client.dart';
import 'lichess_puzzle_repository.dart';
import 'puzzle_repository.dart';

/// Status des aktuellen Puzzle-Durchgangs.
enum PuzzleStatus {
  loading,
  showingOpponentMove,
  waitingForPlayerMove,
  correct,
  incorrect,
  solved,
  errorNetwork,
  errorServer,
  errorParse,
  error,
}

class PuzzleSessionState extends ChangeNotifier {
  final ChessBoard board = ChessBoard();
  final PuzzleRepository repository;

  PuzzleSessionState({PuzzleRepository? repository})
      : repository = repository ?? LichessPuzzleRepository();

  Puzzle? _currentPuzzle;
  Puzzle? get currentPuzzle => _currentPuzzle;

  PuzzleStatus _status = PuzzleStatus.loading;
  PuzzleStatus get status => _status;

  int _moveIndex = 0;
  List<int> validMovesForSelected = [];
  ChessPiece? selectedPiece;
  Move? latestMove;
  int? incorrectFromTile;
  int? incorrectToTile;
  String? errorMessage;

  bool _disposed = false;
  Timer? _delayTimer;

  @override
  void dispose() {
    _disposed = true;
    _delayTimer?.cancel();
    super.dispose();
  }

  bool _isLoading = false;

  Future<void> loadNextPuzzle() async {
    if (_isLoading) return; // Cooldown / Re-Entrancy Check
    _isLoading = true;
    _setStatus(PuzzleStatus.loading);
    _reset();
    try {
      final puzzle = await repository.getNextPuzzle();
      if (_disposed) return;
      _currentPuzzle = puzzle;
      board.loadFEN(puzzle.fen);
      _moveIndex = 0;
      _scheduleOpponentMove();
    } on PuzzleNetworkException catch (e) {
      errorMessage = e.message;
      _setStatus(PuzzleStatus.errorNetwork);
    } on PuzzleServerException catch (e) {
      errorMessage = e.message;
      _setStatus(PuzzleStatus.errorServer);
    } on PuzzleParseException catch (e) {
      errorMessage = e.message;
      _setStatus(PuzzleStatus.errorParse);
    } catch (e) {
      errorMessage = e.toString();
      _setStatus(PuzzleStatus.error);
    } finally {
      _isLoading = false;
    }
  }

  /// Verarbeitet einen Brett-Tap des Spielers (Feld-Index 0–63).
  void handleTap(int tile) {
    if (_status != PuzzleStatus.waitingForPlayerMove) return;
    final puzzle = _currentPuzzle;
    if (puzzle == null) return;

    final tappedPiece = board.tiles[tile];

    if (selectedPiece == null) {
      // Figur auswählen (nur eigene Figur, basierend auf welche Seite
      // der Spieler in diesem Puzzle spielt — bestimmt durch _moveIndex 1)
      final playerSide = _playerSide(puzzle);
      if (tappedPiece != null && tappedPiece.player == playerSide) {
        selectedPiece = tappedPiece;
        validMovesForSelected = board.movesForPiece(tappedPiece, legal: true);
        notifyListeners();
      }
      return;
    }

    if (tappedPiece == selectedPiece) {
      // Deselektieren
      _clearSelection();
      return;
    }

    // Re-select eigene Figur
    final playerSide = _playerSide(puzzle);
    if (tappedPiece != null &&
        tappedPiece.player == playerSide &&
        !validMovesForSelected.contains(tile)) {
      selectedPiece = tappedPiece;
      validMovesForSelected = board.movesForPiece(tappedPiece, legal: true);
      notifyListeners();
      return;
    }

    // Zug versuchen
    if (validMovesForSelected.contains(tile)) {
      final move = Move(selectedPiece!.tile, tile);
      _clearSelection();
      _handleMove(move, puzzle);
    } else {
      _clearSelection();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Internal Logic
  // ─────────────────────────────────────────────────────────────────────────

  void _reset() {
    _currentPuzzle = null;
    _moveIndex = 0;
    validMovesForSelected = [];
    selectedPiece = null;
    latestMove = null;
    incorrectFromTile = null;
    incorrectToTile = null;
    errorMessage = null;
    _delayTimer?.cancel();
  }

  void _setStatus(PuzzleStatus s) {
    _status = s;
    if (!_disposed) notifyListeners();
  }

  void _clearSelection() {
    selectedPiece = null;
    validMovesForSelected = [];
    notifyListeners();
  }

  /// Bestimmt die Spielerseite im aktuellen Puzzle.
  /// In solutionMoves ist Index 0 = Gegner, Index 1 = Spieler.
  /// Die Seite des Spielers ist die Seite, die an Zug 1 dran ist.
  Player _playerSide(Puzzle puzzle) {
    // Lade FEN, um herauszufinden wer nach dem Gegnerzug dran ist.
    // Nach board.loadFEN + board.push(opponentMove) ist board.tiles befüllt.
    // Wir leiten die Seite einfach aus dem aktuellen moveStack ab.
    // Der Gegnerzug ist bereits ausgeführt, also ist jetzt der Spieler dran.
    // Wir erkennen das an der Farbe, die jetzt am Zug ist.
    // Einfachste Methode: prüfen, welche Seite bei moveIndex=1 spielen sollte.
    // Das ist die Seite, die NICHT den letzten Zug ausgeführt hat.
    if (board.moveStack.isEmpty) return Player.player1;
    final lastMover = board.moveStack.last.movedPiece?.player;
    if (lastMover == Player.player1) return Player.player2;
    return Player.player1;
  }

  void _scheduleOpponentMove() {
    _setStatus(PuzzleStatus.showingOpponentMove);
    _delayTimer = Timer(const Duration(milliseconds: 500), () {
      if (_disposed) return;
      _executeOpponentMove();
    });
  }

  void _executeOpponentMove() {
    final puzzle = _currentPuzzle;
    if (puzzle == null || puzzle.solutionMoves.isEmpty) return;

    final uci = puzzle.solutionMoves[0];
    try {
      final move = uciToMove(uci, board);
      board.push(move);
      latestMove = move;
      _moveIndex = 1;
      _setStatus(PuzzleStatus.waitingForPlayerMove);
    } catch (e) {
      errorMessage = 'Fehler beim Ausführen des Gegnerzugs: $e';
      _setStatus(PuzzleStatus.error);
    }
  }

  void _handleMove(Move move, Puzzle puzzle) {
    final expectedUci = puzzle.solutionMoves[_moveIndex];
    final playedUci = _moveToUci(move, board);

    // Zug ausführen (commit auf dem Board)
    board.push(move);
    latestMove = move;

    if (playedUci == expectedUci) {
      _moveIndex++;
      _setStatus(PuzzleStatus.correct);

      // Ist das der letzte Zug?
      if (_moveIndex >= puzzle.solutionMoves.length) {
        // Puzzle gelöst
        _delayTimer = Timer(const Duration(milliseconds: 400), () {
          if (_disposed) return;
          _setStatus(PuzzleStatus.solved);
        });
        return;
      }

      // Nächsten Gegner-Antwort-Zug automatisch ausführen
      _delayTimer = Timer(const Duration(milliseconds: 400), () {
        if (_disposed) return;
        _executeReplyMove(puzzle);
      });
    } else {
      // Falscher Zug – Highlighting, dann zurücknehmen
      incorrectFromTile = move.from;
      incorrectToTile = move.to;
      _setStatus(PuzzleStatus.incorrect);

      _delayTimer = Timer(const Duration(milliseconds: 700), () {
        if (_disposed) return;
        board.pop();
        latestMove = board.moveStack.isNotEmpty ? board.moveStack.last.move : null;
        incorrectFromTile = null;
        incorrectToTile = null;
        _setStatus(PuzzleStatus.waitingForPlayerMove);
      });
    }
  }

  /// Führt den nächsten Antwort-Zug des "Gegners" (aus der Lösung) aus.
  void _executeReplyMove(Puzzle puzzle) {
    if (_moveIndex >= puzzle.solutionMoves.length) {
      _setStatus(PuzzleStatus.solved);
      return;
    }
    final uci = puzzle.solutionMoves[_moveIndex];
    try {
      final move = uciToMove(uci, board);
      board.push(move);
      latestMove = move;
      _moveIndex++;

      // Ist das der letzte Zug?
      if (_moveIndex >= puzzle.solutionMoves.length) {
        _setStatus(PuzzleStatus.solved);
        return;
      }

      _setStatus(PuzzleStatus.waitingForPlayerMove);
    } catch (e) {
      errorMessage = 'Fehler beim Ausführen des Antwort-Zugs: $e';
      _setStatus(PuzzleStatus.error);
    }
  }

  /// Konvertiert ein [Move]-Objekt zurück in einen UCI-String.
  /// Umkehrfunktion von [uciToMove].
  ///
  /// Konvention in ChessBoard:
  /// - tile = rank * 8 + file, wobei rank 0 = 8. Reihe (Schwarz), rank 7 = 1. Reihe (Weiß)
  /// - Castling: king-captures-rook intern → standard UCI extern.
  static String _moveToUci(Move move, ChessBoard board) {
    // Castling-Rückübersetzung (intern: König nimmt eigenen Turm)
    if (move.from == 60 && move.to == 63) return 'e1g1'; // Weißkurze Rochade
    if (move.from == 60 && move.to == 56) return 'e1c1'; // Weißlange Rochade
    if (move.from == 4 && move.to == 7) return 'e8g8'; // Schwarzkurze Rochade
    if (move.from == 4 && move.to == 0) return 'e8c8'; // Schwarzlange Rochade

    final fromRank = move.from ~/ 8;
    final fromFile = move.from % 8;
    final toRank = move.to ~/ 8;
    final toFile = move.to % 8;

    // rank 0 → '8', rank 7 → '1'
    final fromStr =
        String.fromCharCode(fromFile + 97) + (8 - fromRank).toString();
    final toStr = String.fromCharCode(toFile + 97) + (8 - toRank).toString();

    String uci = '$fromStr$toStr';

    // Promotion-Suffix
    if (move.promotionType != ChessPieceType.promotion) {
      switch (move.promotionType) {
        case ChessPieceType.queen:
          uci += 'q';
          break;
        case ChessPieceType.rook:
          uci += 'r';
          break;
        case ChessPieceType.bishop:
          uci += 'b';
          break;
        case ChessPieceType.knight:
          uci += 'n';
          break;
        default:
          break;
      }
    }

    return uci;
  }
}
