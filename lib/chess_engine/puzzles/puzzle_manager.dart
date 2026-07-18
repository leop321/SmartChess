import '../chess_logic/chess_state.dart';
import '../chess_logic/move_parser.dart';
import '../speech/speech_service.dart';
import 'puzzle.dart';

class PuzzleManager {
  final ChessSpeechService _speechService;
  late ChessState chessState;
  
  ChessPuzzle? _currentPuzzle;
  int _currentMoveIndex = 0;
  bool _isCompleted = false;
  bool _hasFailed = false;

  PuzzleManager(this._speechService) {
    chessState = ChessState();
  }

  ChessPuzzle? get currentPuzzle => _currentPuzzle;
  int get currentMoveIndex => _currentMoveIndex;
  bool get isCompleted => _isCompleted;
  bool get hasFailed => _hasFailed;

  /// Loads a chess puzzle and resets the board to its starting FEN.
  void loadPuzzle(ChessPuzzle puzzle) {
    _currentPuzzle = puzzle;
    _currentMoveIndex = 0;
    _isCompleted = false;
    _hasFailed = false;
    chessState.reset(fen: puzzle.startingFen);
  }

  /// Attempts to play the user's move (represented in UCI, e.g. 'd2d4' or 'd5c7').
  /// Returns [true] if the move was correct, or [false] if it was incorrect.
  Future<bool> playUserMove(String uciMove) async {
    final puzzle = _currentPuzzle;
    if (puzzle == null || _isCompleted) return false;

    // Check if user's move matches the expected solution move at the current index.
    final expectedMove = puzzle.solutionMoves[_currentMoveIndex];
    if (uciMove.toLowerCase() != expectedMove.toLowerCase()) {
      _hasFailed = true;
      return false;
    }

    // Apply user move
    final san = chessState.makeMove(uciMove);
    if (san == null) {
      // Should not happen if the solution is valid, but safeguard
      return false;
    }

    // Reset failure state on correct move
    _hasFailed = false;

    // Play user move sound tokens
    final userTokens = MoveParser.parseSan(san);
    await _speechService.playMove(userTokens);

    _currentMoveIndex++;

    // Check if the puzzle is completed
    if (_currentMoveIndex >= puzzle.solutionMoves.length) {
      _isCompleted = true;
      return true;
    }

    // Play opponent's response automatically
    final opponentExpectedMove = puzzle.solutionMoves[_currentMoveIndex];
    
    // We add a small delay before opponent replies so it sounds natural
    await Future.delayed(const Duration(milliseconds: 800));

    final opponentSan = chessState.makeMove(opponentExpectedMove);
    if (opponentSan != null) {
      final opponentTokens = MoveParser.parseSan(opponentSan);
      await _speechService.playMove(opponentTokens);
    }

    _currentMoveIndex++;

    // Check if the puzzle is completed after opponent move
    if (_currentMoveIndex >= puzzle.solutionMoves.length) {
      _isCompleted = true;
    }

    return true;
  }
}
