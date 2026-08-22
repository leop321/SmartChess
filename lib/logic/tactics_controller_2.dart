import 'package:flutter/material.dart';
import '../model/app_model.dart';
import '../model/puzzle_model.dart';
import 'puzzle_service.dart';
import 'game_controller.dart';
import 'chess_piece.dart';
import 'move_calculation/move_classes/move.dart';

enum PuzzleStatus { loading, playing, correct, wrong, solved, error }

class TacticsController2 extends ChangeNotifier {
  final AppModel globalAppModel;
  final AppModel puzzleAppModel;
  late GameController puzzleGameController;
  final PuzzleService puzzleService = PuzzleService();

  PuzzleModel? currentPuzzle;
  PuzzleStatus status = PuzzleStatus.loading;
  String errorMessage = '';

  int currentMoveIndex = 0;

  TacticsController2(this.globalAppModel, this.puzzleAppModel) {
    puzzleGameController = GameController(puzzleAppModel);
    puzzleGameController.onUserMoveCompleted = _handleUserMove;
  }

  Future<void> fetchDailyPuzzle() async {
    status = PuzzleStatus.loading;
    notifyListeners();
    try {
      currentPuzzle = await puzzleService.getDailyPuzzle();
      _initializePuzzle();
    } catch (e) {
      status = PuzzleStatus.error;
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> fetchRandomPuzzle() async {
    // Using daily puzzle for now, can be extended to random endpoint if needed
    await fetchDailyPuzzle();
  }

  void _initializePuzzle() {
    if (currentPuzzle == null) return;
    currentMoveIndex = 0;

    // Convert FEN and load
    // Lichess puzzle FEN is the position to solve with the correct side to move.
    // The solution array starts with the player's move, not the opponent's.
    puzzleGameController.loadFEN(currentPuzzle!.fen);

    if (currentPuzzle!.moves.isNotEmpty) {
      status = PuzzleStatus.playing;
      notifyListeners();
      // Do NOT auto-play opponent move - wait for user's first move
    } else {
      status = PuzzleStatus.error;
      errorMessage = "No moves in puzzle";
      notifyListeners();
    }
  }

  void _playOpponentNextMove() async {
    if (currentMoveIndex >= currentPuzzle!.moves.length) {
      status = PuzzleStatus.solved;
      globalAppModel.recordPuzzleResult(currentPuzzle!.rating.toDouble(), true);
      notifyListeners();
      return;
    }

    final moveStr = currentPuzzle!.moves[currentMoveIndex];
    final move = _uciToMove(moveStr);

    // Add small delay to simulate opponent thinking
    await Future.delayed(const Duration(milliseconds: 600));

    puzzleGameController.executeOpponentMove(move);
    currentMoveIndex++;

    if (currentMoveIndex >= currentPuzzle!.moves.length) {
      status = PuzzleStatus.solved;
      globalAppModel.recordPuzzleResult(currentPuzzle!.rating.toDouble(), true);
    }
    notifyListeners();
  }

  bool _handleUserMove(Move userMove) {
    if (currentPuzzle == null ||
        currentMoveIndex >= currentPuzzle!.moves.length) return false;

    final expectedMoveStr = currentPuzzle!.moves[currentMoveIndex];
    final expectedMove = _uciToMove(expectedMoveStr);

    // Compare moves
    if (userMove.from == expectedMove.from && userMove.to == expectedMove.to) {
      // Correct!
      status = PuzzleStatus.correct;
      globalAppModel.puzzleRetries = 0; // reset local retries
      notifyListeners();

      currentMoveIndex++;

      if (currentMoveIndex < currentPuzzle!.moves.length) {
        _playOpponentNextMove();
      } else {
        status = PuzzleStatus.solved;
        globalAppModel.recordPuzzleResult(
            currentPuzzle!.rating.toDouble(), true);
        notifyListeners();
      }
      return true; // allow execution
    } else {
      // Wrong move
      status = PuzzleStatus.wrong;
      globalAppModel.puzzleRetries++;
      if (globalAppModel.puzzleRetries == 1) {
        // if first wrong, mark as loss for streak
        globalAppModel.recordPuzzleResult(
            currentPuzzle!.rating.toDouble(), false);
      }
      notifyListeners();

      // We return false to cancel the move.
      return false;
    }
  }

  Move _uciToMove(String uci) {
    // Handle castling
    if (uci == 'e1g1') return Move(60, 63);
    if (uci == 'e1c1') return Move(60, 56);
    if (uci == 'e8g8') return Move(4, 7);
    if (uci == 'e8c8') return Move(4, 0);

    // Standard UCI format: e2e4 or e7e8q (promotion)
    if (uci.length < 4) {
      throw ArgumentError('Invalid UCI move: $uci');
    }

    int fromFile = uci.codeUnitAt(0) - 97;
    int fromRank = 8 - int.parse(uci[1]);
    int toFile = uci.codeUnitAt(2) - 97;
    int toRank = 8 - int.parse(uci[3]);

    // Handle promotion (5th character: q, r, b, n)
    ChessPieceType promotionType = ChessPieceType.promotion;
    if (uci.length >= 5) {
      final promoChar = uci[4].toLowerCase();
      switch (promoChar) {
        case 'q':
          promotionType = ChessPieceType.queen;
          break;
        case 'r':
          promotionType = ChessPieceType.rook;
          break;
        case 'b':
          promotionType = ChessPieceType.bishop;
          break;
        case 'n':
          promotionType = ChessPieceType.knight;
          break;
      }
    }

    return Move(
      fromRank * 8 + fromFile,
      toRank * 8 + toFile,
      promotionType: promotionType,
    );
  }

  void disposeController() {
    puzzleGameController.dispose();
  }
}
