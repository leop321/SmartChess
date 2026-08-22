import 'dart:async';
import 'dart:math' as math;

import 'package:chess/chess.dart' as ch;
import 'package:flutter/widgets.dart';

import '../model/anti_tactics_storage.dart';
import '../model/app_model.dart';
import '../model/lichess_puzzle.dart'; // Keep for PuzzleRecord
import '../model/player.dart';
import '../model/tactics_task.dart';
import 'chess_piece.dart';
import 'game_controller.dart';
import 'move_calculation/move_classes/move.dart';
import 'puzzle_providers/rating_aware_classic_provider.dart';
import 'puzzle_providers/tactics_task_provider.dart';
import 'puzzle_rush_storage.dart';
import 'simple_tactics_queue.dart';
import 'tactics_judge.dart';

enum PuzzleStatus {
  loading, // fetching puzzle from network
  idle, // puzzle loaded, waiting for player
  hintActive, // hint: the correct piece is highlighted
  correct, // last player move was correct
  opponentMoving, // opponent's response is playing
  wrong, // last player move was wrong
  solved, // all moves in solution completed correctly
  resigned, // player gave up
  error, // network error
}

/// ChangeNotifier that manages the full lifecycle of a tactics puzzle session.
class TacticsPuzzleController extends ChangeNotifier
    with WidgetsBindingObserver {
  static const int _kFactor = 20;
  static const int _maxHistoryDisplay = 30;

  final AppModel appModel;
  final TacticsMode mode;
  final TacticsTaskProvider? _provider;
  final TacticsJudge _judge;
  final SimpleTacticsQueue _queue = SimpleTacticsQueue();

  TacticsPuzzleController(
    this.appModel, {
    this.mode = TacticsMode.classic,
    TacticsTaskProvider? provider,
    TacticsJudge? judge,
  })  : _provider = provider,
        _judge = judge ??
            ((mode == TacticsMode.antiTactics ||
                    mode == TacticsMode.antiTacticsV2)
                ? AntiTacticsJudge()
                : ClassicTacticsJudge()) {
    WidgetsBinding.instance.addObserver(this);
    _loadPersistedData();
    _startSessionTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _queue.persist(mode);
      TacticsStorage.saveRating(_rating, mode: mode.name);
      TacticsStorage.saveHistory(_history, mode: mode.name);
    }
  }

  GameController? gameController;
  Timer? _timer;

  // ── State ──────────────────────────────────────────────────────────────────

  ch.Color _initialPlayerColor = ch.Color.WHITE;

  TacticsTask? _task;
  PuzzleStatus _status = PuzzleStatus.loading;
  String _errorMessage = '';

  /// The `chess` library instance tracking the current board position.
  ch.Chess? _board;

  /// Index of the *next* solution move the player must play.
  /// Even indices = player's move, odd indices = opponent's response.
  int _solutionIndex = 0;

  /// Moves already played in this puzzle (UCI strings).
  final List<String> _playedUciMoves = [];

  /// Current position in the playback view.
  /// -1 = live position. ≥ 0 = viewing a historical position.
  int _historyIndex = -1;

  /// Board snapshots (FEN after each played move) for back/forward navigation.
  final List<String> _fenHistory = [];

  /// Currently selected tile index (0–63, null = none).
  int? _selectedTile;

  /// Legal destination tiles for the currently selected piece.
  List<int> _validDestinations = [];

  /// The tile that should glow for the hint.
  int? _hintTile;

  int _hintCount = 0;
  int _mistakeCount = 0;

  /// Tactics Elo rating of the player.
  int _rating = 1200;

  /// Session history across all puzzles.
  final List<PuzzleRecord> _history = [];

  int _elapsedSeconds = 0;

  int _sessionElapsedSeconds = 0;
  Timer? _sessionTimer;
  int _sessionSolved = 0;
  int _sessionAttempted = 0;

  void _startSessionTimer() {
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _sessionElapsedSeconds++;
      notifyListeners();
    });
  }

  // ── Getters ────────────────────────────────────────────────────────────────

  TacticsTask? get task => _task;
  PuzzleStatus get status => _status;
  String get errorMessage => _errorMessage;
  int? get selectedTile => _selectedTile;
  List<int> get validDestinations => _validDestinations;
  int? get hintTile => _hintTile;
  bool get hintUsed => _hintCount > 0;
  int get hintCount => _hintCount;
  int get mistakeCount => _mistakeCount;
  int get rating => _rating;
  List<PuzzleRecord> get history => List.unmodifiable(_history);
  List<String> get playedUciMoves => List.unmodifiable(_playedUciMoves);
  bool get isViewingHistory => _historyIndex >= 0;
  bool get canGoBack => _playedUciMoves.isNotEmpty && _historyIndex != 0;
  bool get canGoForward => _historyIndex >= 0;

  int get sessionElapsedSeconds => _sessionElapsedSeconds;
  int get sessionSolved => _sessionSolved;
  int get sessionAttempted => _sessionAttempted;
  int get elapsedSeconds => _elapsedSeconds;
  ch.Color get playerColor => _initialPlayerColor;

  /// Returns the FEN string for the current display position.
  String get displayFen {
    if (_board == null) return ch.Chess.DEFAULT_POSITION;
    if (_historyIndex >= 0 && _historyIndex < _fenHistory.length) {
      return _fenHistory[_historyIndex];
    }
    return _board!.fen;
  }

  /// The move that set up the puzzle (for last-move highlight on load).
  String? get setupLastMove => _task?.lastMove;

  /// Highlight for the last move in the display position.
  String? get displayLastMove {
    if (_historyIndex == -1) {
      // Live: show the last played move (or setup move if no moves played yet)
      if (_playedUciMoves.isNotEmpty) return _playedUciMoves.last;
      return _task?.lastMove;
    }
    if (_historyIndex == 0) return _task?.lastMove;
    return _playedUciMoves[_historyIndex - 1];
  }

  /// True if we're currently in the live position (not browsing history).
  bool get isLivePosition => _historyIndex == -1;

  // ── Init ───────────────────────────────────────────────────────────────────

  Future<void> _loadPersistedData() async {
    _rating = await TacticsStorage.loadRating(mode: mode.name);
    final saved = await TacticsStorage.loadHistory(mode: mode.name);
    _history.clear();
    _history.addAll(saved);

    if (mode == TacticsMode.antiTactics || mode == TacticsMode.antiTacticsV2) {
      await AntiTacticsStorage.instance.init();
    }

    if (_provider != null) {
      notifyListeners();
      fetchNextPuzzle();
    } else {
      await _queue.restore(mode);
      _loadTaskFromQueue(_queue.current);
    }
  }

  AntiTacticsStats? get antiTacticsStats =>
      (mode == TacticsMode.antiTactics || mode == TacticsMode.antiTacticsV2)
          ? AntiTacticsStorage.instance.stats
          : null;

  // ── Puzzle Fetching ────────────────────────────────────────────────────────

  /// Advances to the next puzzle from the offline 3-puzzle queue and resets all session state.
  Future<void> fetchNextPuzzle() async {
    _status = PuzzleStatus.loading;
    _task = null;
    _board = null;
    _solutionIndex = 0;
    _playedUciMoves.clear();
    _fenHistory.clear();
    _historyIndex = -1;
    _selectedTile = null;
    _validDestinations = [];
    _hintTile = null;
    _hintCount = 0;
    _mistakeCount = 0;
    _timer?.cancel();
    _elapsedSeconds = 0;
    _errorMessage = '';
    notifyListeners();

    try {
      TacticsTask? task;
      if (_provider != null) {
        task = await _provider!.fetchNextTask();
      } else {
        task = await _queue.advance(mode);
      }

      if (task != null) {
        _loadTaskFromQueue(task);
      } else {
        _status = PuzzleStatus.error;
        _errorMessage = 'Keine Aufgaben verfügbar';
      }
    } catch (e) {
      _errorMessage = e.toString();
      _status = PuzzleStatus.error;
    }
    notifyListeners();
  }

  void _loadTaskFromQueue(TacticsTask? task) {
    if (task == null) return;
    _task = task;
    _board = ch.Chess.fromFEN(task.fen);
    _initialPlayerColor = _board!.turn;
    _fenHistory.clear();
    _fenHistory.add(_board!.fen); // snapshot[0] = initial position

    if (gameController != null) {
      gameController!.appModel.playerSide =
          _initialPlayerColor == ch.Color.WHITE
              ? Player.player1
              : Player.player2;
      gameController!.loadFEN(task.fen);
    }

    _status = PuzzleStatus.idle;
    _startTimer();
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status == PuzzleStatus.idle ||
          _status == PuzzleStatus.hintActive ||
          _status == PuzzleStatus.wrong ||
          _status == PuzzleStatus.correct ||
          _status == PuzzleStatus.opponentMoving) {
        _elapsedSeconds++;
        notifyListeners();
      }
    });
  }

  // ── Move Input ─────────────────────────────────────────────────────────────

  /// Called when the player attempts a move via GameController.
  /// Returns true if the move is allowed to execute, false otherwise.
  bool handleUserMove(Move move) {
    if (_task == null || _board == null) return false;
    if (_status != PuzzleStatus.idle &&
        _status != PuzzleStatus.hintActive &&
        _status != PuzzleStatus.wrong &&
        _status != PuzzleStatus.correct) return false;

    if (isViewingHistory) {
      goToLive();
      return false;
    }

    String fromSq;
    String toSq;
    String? promoChar;

    if (move.from == 60 && move.to == 63) {
      fromSq = 'e1';
      toSq = 'g1';
    } else if (move.from == 60 && move.to == 56) {
      fromSq = 'e1';
      toSq = 'c1';
    } else if (move.from == 4 && move.to == 7) {
      fromSq = 'e8';
      toSq = 'g8';
    } else if (move.from == 4 && move.to == 0) {
      fromSq = 'e8';
      toSq = 'c8';
    } else {
      fromSq = _tileToAlgebraic(move.from);
      toSq = _tileToAlgebraic(move.to);

      if (move.promotionType == ChessPieceType.queen)
        promoChar = 'q';
      else if (move.promotionType == ChessPieceType.rook)
        promoChar = 'r';
      else if (move.promotionType == ChessPieceType.bishop)
        promoChar = 'b';
      else if (move.promotionType == ChessPieceType.knight) promoChar = 'n';

      // Promotion-Erkennung für MVP: Wenn ein Bauer die letzte Reihe betritt,
      // gehen wir vereinfacht von einer Queen-Promotion aus.
      final piece = _board!.get(fromSq);
      if (piece != null && piece.type == ch.PieceType.PAWN) {
        if (toSq.endsWith('8') || toSq.endsWith('1')) {
          promoChar ??= 'q';
        }
      }
    }

    _selectedTile = null;
    _validDestinations = [];
    _hintTile = null;

    final uci = '$fromSq$toSq${promoChar ?? ''}';
    final result = _judge.evaluateMove(_task!, _solutionIndex, uci);

    if (result.verdict == JudgeVerdict.correct ||
        result.verdict == JudgeVerdict.solved) {
      _applyMove(fromSq, toSq, promoChar);
      _solutionIndex++;

      if (result.verdict == JudgeVerdict.solved) {
        Future.delayed(
            const Duration(milliseconds: 500), () => _finalize(solved: true));
      } else {
        _status = PuzzleStatus.correct;
        notifyListeners();
        Future.delayed(const Duration(milliseconds: 600), _playOpponentMove);
      }
      return true;
    } else if (result.verdict == JudgeVerdict.wrong) {
      _mistakeCount++;
      _status = PuzzleStatus.wrong;
      if (result.feedback != null) {
        _errorMessage = result.feedback!;
      }
      notifyListeners();

      Future.delayed(const Duration(milliseconds: 800), () {
        if (_status == PuzzleStatus.wrong) {
          _status = PuzzleStatus.idle;
          _errorMessage = '';
          notifyListeners();
        }
      });
      return false;
    }
    return false;
  }

  void handleAction(TacticsAction action) {
    if (_task == null || _status != PuzzleStatus.idle) return;

    final result = _judge.evaluateAction(_task!, action);

    if (result.verdict == JudgeVerdict.solved) {
      appModel.haptic.medium();
      appModel.audio.playMovedSound();
      _finalize(solved: true);
    } else if (result.verdict == JudgeVerdict.wrong) {
      _mistakeCount++;
      appModel.haptic.heavy();
      _status = PuzzleStatus.wrong;
      if (result.feedback != null) {
        _errorMessage = result.feedback!;
      }
      notifyListeners();

      Future.delayed(const Duration(milliseconds: 800), () {
        if (_status == PuzzleStatus.wrong) {
          _status = PuzzleStatus.idle;
          _errorMessage = '';
          notifyListeners();
        }
      });
    }
  }

  void _applyMove(String from, String to, String? promoChar) {
    final moveArgs = <String, String>{'from': from, 'to': to};
    if (promoChar != null) moveArgs['promotion'] = promoChar;
    _board!.move(moveArgs);
    _playedUciMoves.add('$from$to${promoChar ?? ''}');
    _fenHistory.add(_board!.fen);
  }

  Future<void> _playOpponentMove() async {
    if (_task == null ||
        _board == null ||
        _solutionIndex >= _task!.expectedMoves.length) return;

    _status = PuzzleStatus.opponentMoving;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 500));

    final oppUci = _task!.expectedMoves[_solutionIndex];
    final oppFrom = oppUci.substring(0, 2);
    final oppTo = oppUci.substring(2, 4);
    final promoChar = oppUci.length > 4 ? oppUci.substring(4) : null;

    _applyMove(oppFrom, oppTo, promoChar);

    if (gameController != null) {
      Move oppMove;
      if (oppUci == 'e1g1') {
        oppMove = Move(60, 63);
      } else if (oppUci == 'e1c1') {
        oppMove = Move(60, 56);
      } else if (oppUci == 'e8g8') {
        oppMove = Move(4, 7);
      } else if (oppUci == 'e8c8') {
        oppMove = Move(4, 0);
      } else {
        int fromFile = oppFrom.codeUnitAt(0) - 97;
        int fromRank = 8 - int.parse(oppFrom[1]);
        int toFile = oppTo.codeUnitAt(0) - 97;
        int toRank = 8 - int.parse(oppTo[1]);
        oppMove = Move(fromRank * 8 + fromFile, toRank * 8 + toFile);
        if (promoChar != null) {
          if (promoChar == 'q')
            oppMove.promotionType = ChessPieceType.queen;
          else if (promoChar == 'r')
            oppMove.promotionType = ChessPieceType.rook;
          else if (promoChar == 'b')
            oppMove.promotionType = ChessPieceType.bishop;
          else if (promoChar == 'n')
            oppMove.promotionType = ChessPieceType.knight;
        }
      }
      gameController!.executeOpponentMove(oppMove);
    } else {
      appModel.haptic.medium();
      appModel.audio.playMovedSound();
    }

    _solutionIndex++;

    if (_solutionIndex >= _task!.expectedMoves.length) {
      _finalize(solved: true);
    } else {
      _status = PuzzleStatus.idle;
      notifyListeners();
    }
  }

  // ── Resign ────────────────────────────────────────────────────────────────

  void resign() {
    if (_status == PuzzleStatus.loading ||
        _status == PuzzleStatus.resigned ||
        _status == PuzzleStatus.solved) return;
    _finalize(solved: false, resign: true);
  }

  // ── Hint ──────────────────────────────────────────────────────────────────

  void requestHint() {
    if (_task == null) return;
    if (_status != PuzzleStatus.idle) return;
    if (_solutionIndex >= _task!.expectedMoves.length) return;
    if (isViewingHistory) return;

    _hintCount++;
    final nextUci = _task!.expectedMoves[_solutionIndex];
    final fromSq = nextUci.substring(0, 2);
    _hintTile = _algebraicToTile(fromSq);
    _selectedTile = null;
    _validDestinations = [];
    _status = PuzzleStatus.hintActive;

    if (gameController != null && _hintTile != null) {
      final piece = gameController!.board.tiles[_hintTile!];
      if (piece != null) {
        gameController!.selectPiece(piece);
      }
    }

    notifyListeners();
  }

  // ── History Navigation ─────────────────────────────────────────────────────

  void goBack() {
    if (!canGoBack) return;
    if (_historyIndex == -1) {
      // Go from live to last played move
      _historyIndex = _playedUciMoves.length - 1;
    } else if (_historyIndex > 0) {
      _historyIndex--;
    }
    _selectedTile = null;
    _validDestinations = [];
    if (gameController != null) {
      gameController!.loadFEN(displayFen);
    }
    notifyListeners();
  }

  void goForward() {
    if (!canGoForward) return;
    if (_historyIndex < _playedUciMoves.length - 1) {
      _historyIndex++;
    } else {
      // Back to live
      _historyIndex = -1;
    }
    _selectedTile = null;
    _validDestinations = [];
    if (gameController != null) {
      gameController!.loadFEN(displayFen);
    }
    notifyListeners();
  }

  void goToLive() {
    _historyIndex = -1;
    _selectedTile = null;
    _validDestinations = [];
    if (gameController != null) {
      gameController!.loadFEN(displayFen);
    }
    notifyListeners();
  }

  // ── Rating & Finalize ─────────────────────────────────────────────────────

  void _finalize({required bool solved, bool resign = false}) {
    if (_task == null) return;
    _timer?.cancel();

    // Use the display rating (real puzzle difficulty) for Elo calculation,
    // not the inflated searchRating which would make deltas non-meaningful.
    final puzzleRating = _task!.effectiveDisplayRating;
    final expected =
        1.0 / (1.0 + math.pow(10.0, (puzzleRating - _rating) / 400.0));

    double score = 1.0;
    if (resign) {
      score = 0.0;
    } else {
      // Graduated Performance Score
      score =
          (1.0 - (0.4 * _mistakeCount) - (0.3 * _hintCount)).clamp(0.0, 1.0);
    }

    int delta = (_kFactor * (score - expected)).round();
    if ((mode == TacticsMode.antiTactics ||
            mode == TacticsMode.antiTacticsV2) &&
        delta > 0) {
      delta = (delta / 3.0).round();
    }
    final newRating = (_rating + delta).clamp(100, 3200);

    final record = PuzzleRecord(
      puzzleId: _task!.id,
      ratingChange: delta,
      solved: solved,
      elapsedSeconds: _elapsedSeconds,
    );
    _history.insert(0, record);
    if (_history.length > _maxHistoryDisplay) {
      _history.removeRange(_maxHistoryDisplay, _history.length);
    }

    _rating = newRating;
    TacticsStorage.saveRating(_rating, mode: mode.name);
    TacticsStorage.saveHistory(_history, mode: mode.name);

    if (mode == TacticsMode.antiTactics || mode == TacticsMode.antiTacticsV2) {
      AntiTacticsStorage.instance.recordResult(
        id: _task!.id,
        solved: solved,
        isNoWinningTactic:
            _task!.antiTacticsType == AntiTacticsType.noWinningTactic,
      );
    }

    _sessionAttempted++;
    if (solved) {
      _sessionSolved++;
      appModel.haptic.medium();
    } else {
      appModel.haptic.heavy();
    }

    // Save Puzzle Rush record if running in puzzleRush mode
    if (mode == TacticsMode.puzzleRush) {
      PuzzleRushStorage.loadConfig().then((config) {
        PuzzleRushStorage.saveRunRecord(
          score: _sessionSolved,
          bestStreak: _sessionSolved,
          config: config,
        );
      });
    }

    _status = solved ? PuzzleStatus.solved : PuzzleStatus.resigned;
    notifyListeners();
  }

  // ── Coordinate Helpers ────────────────────────────────────────────────────

  /// Converts a 0–63 tile index (rank 0 = top/row 8, file 0 = a) to
  /// algebraic notation ('a8'…'h1') matching the chess package's convention.
  static String _tileToAlgebraic(int tile) {
    final file = tile % 8;
    final rank = tile ~/ 8;
    return '${String.fromCharCode(97 + file)}${8 - rank}';
  }

  /// Converts algebraic ('a8'…'h1') back to a 0–63 tile index.
  static int _algebraicToTile(String sq) {
    final file = sq.codeUnitAt(0) - 97;
    final rank = 8 - int.parse(sq[1]);
    return rank * 8 + file;
  }

  // ── Review Puzzle ─────────────────────────────────────────────────────────

  /// Loads a puzzle from history and enters review mode (replays solution).
  Future<void> reviewPuzzle(String puzzleId) async {
    if (_status == PuzzleStatus.loading) return;
    _timer?.cancel();
    _status = PuzzleStatus.loading;
    _task = null;
    _board = null;
    _playedUciMoves.clear();
    _fenHistory.clear();
    _historyIndex = -1;
    _selectedTile = null;
    _validDestinations = [];
    _hintTile = null;
    _hintCount = 0;
    _mistakeCount = 0;
    notifyListeners();

    try {
      final provider = _provider ?? RatingAwareClassicProvider();
      final task = await provider.fetchTaskById(puzzleId);
      _task = task;
      _board = ch.Chess.fromFEN(task.fen);
      _initialPlayerColor = _board!.turn;
      _fenHistory.add(_board!.fen);

      // Load elapsed seconds if we can find this puzzle in history
      final record = _history.where((r) => r.puzzleId == puzzleId).firstOrNull;
      _elapsedSeconds = record?.elapsedSeconds ?? 0;

      // Play out the entire solution
      for (final moveUci in task.expectedMoves) {
        final from = moveUci.substring(0, 2);
        final to = moveUci.substring(2, 4);
        final promoChar = moveUci.length > 4 ? moveUci.substring(4) : null;
        _applyMove(from, to, promoChar);
      }

      _solutionIndex = task.expectedMoves.length;
      _historyIndex =
          _playedUciMoves.length - 1; // Start at the final solved position
      _status = PuzzleStatus.solved;
      if (gameController != null) {
        gameController!.loadFEN(displayFen);
      }
    } catch (e) {
      _errorMessage = 'Failed to load puzzle: $e';
      _status = PuzzleStatus.error;
    }
    notifyListeners();
  }

  bool _isDisposed = false;

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _sessionTimer?.cancel();
    super.dispose();
  }
}
