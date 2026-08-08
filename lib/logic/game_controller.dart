import 'dart:math' as math;
import 'package:async/async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chess_engine/chess_logic/chess_state.dart';
import '../chess_engine/chess_logic/move_parser.dart';
import '../model/api_models.dart';
import '../model/app_model.dart';
import '../model/player.dart';
import 'bot_settings_notifier.dart';
import 'checkmate_isolate.dart';
import 'checkmate_worker.dart';
import 'chess_board.dart';
import 'chess_piece.dart';
import 'game_mode_notifier.dart';
import 'move_calculation/move_classes/move.dart';
import 'move_calculation/move_classes/move_meta.dart';
import 'peeking_notifier.dart';
import 'play_games_service.dart';
import 'remote_ai_service.dart';
import 'shared_functions.dart';
import 'stockfish_service.dart';

final providerContainer = ProviderContainer();

/// Handles game logic orchestration: move execution, AI, undo/redo, promotion.
/// Separated from ChessGame (the view/rendering layer) for clean MVVM.
class GameController {
  final AppModel appModel;
  final ChessBoard board = ChessBoard();

  RemoteAiService get _aiService =>
      providerContainer.read(remoteAiServiceProvider);

  CancelableOperation? aiOperation;
  List<int> validMoves = [];
  ChessPiece? selectedPiece;
  int? checkHintTile;
  int? warningTile;
  Move? latestMove;
  DateTime? _userMoveTime;

  /// Whether the Flame layer should hide pieces (Snapshot / Blind modes).
  bool boardFrozen = false;
  bool isResumingPeek = false;
  int? snapshotMoveCount;

  /// Persistent background isolate for checkmate detection.
  /// Spawned once at construction so it is warm before the first move.
  CheckmateWorker? _checkmateWorker;

  /// Called when the view needs to refresh sprites (e.g. after game restore).
  void Function({bool snap})? onSnapSprites;

  /// Optional callback invoked when the user attempts a move.
  /// Return true to allow the move to complete, or false to revert it.
  bool Function(Move move)? onUserMoveCompleted;

  GameController(this.appModel) {
    if (appModel.gameMode == ChessMode.snapshot ||
        appModel.gameMode == ChessMode.blind) {
      boardFrozen = true;
    }

    // Spawn the worker asynchronously so construction is synchronous.
    // By the time the first move is played the isolate will already be warm.
    CheckmateWorker.create().then((worker) {
      _checkmateWorker = worker;
    });
  }

  void loadFEN(String fen) {
    appModel.turn = board.loadFEN(fen);
    validMoves = [];
    selectedPiece = null;
    latestMove = null;
    checkHintTile = null;
    warningTile = null;
    snapSprites(snap: true);
  }

  // ── Piece Selection ──

  /// Routing logic for a board tap at [tile].
  ///
  /// Called by the Flame view after it converts a touch position to a tile
  /// index. Contains all tap-routing decisions so the view stays logic-free.
  ///
  /// Guards:
  /// - No input while it's the AI's turn (unless the game is already over).
  /// - Deselect: tapping the already-selected piece clears selection.
  /// - Re-select: tapping a friendly piece swaps selection (or moves if valid).
  /// - Move: tapping any other tile forwards to [movePiece].
  void handleTap(int tile) {
    // In blind and snapshot modes board taps are disabled — moves come from
    // the BlindInputOverlay keyboard instead.
    if (appModel.gameMode != ChessMode.normal) return;
    if (!appModel.gameOver && appModel.isAIsTurn) return;
    final touchedPiece = board.tiles[tile];
    if (touchedPiece == selectedPiece) {
      // Deselect: tap the already-selected piece again.
      validMoves = [];
      selectedPiece = null;
      appModel.haptic.selection();
    } else if (selectedPiece != null &&
        touchedPiece != null &&
        touchedPiece.player == selectedPiece?.player) {
      // Tap a friendly piece while another is selected.
      if (validMoves.contains(tile)) {
        movePiece(tile);
      } else {
        validMoves = [];
        selectPiece(touchedPiece);
      }
    } else if (selectedPiece == null) {
      // No piece selected — try to select this one.
      selectPiece(touchedPiece);
    } else {
      // A piece is selected — try to move to this tile.
      movePiece(tile);
    }
  }

  void selectPiece(ChessPiece? piece) {
    if (piece != null) {
      if (piece.player == appModel.turn) {
        selectedPiece = piece;
        if (selectedPiece != null) {
          validMoves = board.movesForPiece(piece);
        }
        if (validMoves.isEmpty) {
          selectedPiece = null;
          warningTile = piece.tile;
          appModel.haptic.warning();
          appModel.update();
          Future.delayed(const Duration(milliseconds: 500), () {
            if (warningTile == piece.tile) {
              warningTile = null;
              appModel.update();
            }
          });
        } else {
          appModel.haptic.selection();
        }
      }
    }
  }

  void movePiece(int tile) {
    if (validMoves.contains(tile)) {
      validMoves = [];

      final attemptedMove = Move(selectedPiece?.tile ?? 0, tile);

      if (onUserMoveCompleted != null) {
        bool allowed = onUserMoveCompleted!(attemptedMove);
        if (!allowed) {
          // If the move is not allowed by the delegate (e.g. puzzle constraint),
          // don't execute it. Just clear selection.
          selectedPiece = null;
          appModel.haptic.warning();
          appModel.update();
          return;
        }
      }

      var meta = board.push(attemptedMove, getMeta: true);
      appModel.audio.playMovedSound();
      if (meta.promotion) {
        appModel.requestPromotion();
      }
      final playerWhoMoved = appModel.turn;
      _moveCompletion(meta, changeTurn: !meta.promotion);
      // Notify peeking notifier of move completion (non-normal modes only).
      if (appModel.gameMode != ChessMode.normal) {
        providerContainer
            .read(peekingProvider.notifier)
            .handleMoveCompleted(playerWhoMoved);
      }
    } else if (selectedPiece != null) {
      appModel.haptic.warning();
    }
  }

  // ── Blind / Snapshot input ──

  /// Accepts a move string from the blind keyboard (coordinate "e2e4" or SAN
  /// "Nf3") and executes it if it is legal. Returns true on success.
  bool submitBlindMove(String input) {
    if (appModel.gameOver || appModel.isAIsTurn) return false;
    final turn = appModel.turn;

    // Try coordinate notation first, then SAN.
    Move? move = MoveParser.parseCoordinateMove(input) ??
        MoveParser.parseSanMove(input, board, turn);
    if (move == null) return false;

    // Validate the resolved move is actually legal.
    final piece = board.tiles[move.from];
    if (piece == null || piece.player != turn) return false;
    final legal = board.movesForPiece(piece);
    if (!legal.contains(move.to)) return false;

    // Execute — mirror the normal movePiece path.
    selectedPiece = piece;
    validMoves = legal;
    movePiece(move.to);
    return true;
  }

  bool submitDirectMove(Move move) {
    if (appModel.gameOver || appModel.isAIsTurn) return false;
    final piece = board.tiles[move.from];
    if (piece == null || piece.player != appModel.turn) return false;

    final legal = board.movesForPiece(piece);
    if (!legal.contains(move.to)) return false;

    selectedPiece = piece;
    validMoves = legal;
    movePiece(move.to);
    return true;
  }

  /// Executes an opponent's move instantly, bypassing UI validation logic.
  /// Used in Tactics and Anti-Tactics modes.
  void executeOpponentMove(Move move) {
    if (appModel.gameOver) return;

    validMoves = [];
    var meta = board.push(move, getMeta: true);
    appModel.audio.playMovedSound();
    _moveCompletion(meta, changeTurn: !meta.promotion);
    if (meta.promotion) {
      appModel.moveMetaList.last.promotionType = move.promotionType;
      _moveCompletion(appModel.moveMetaList.last, updateMetaList: false);
    }
  }

  /// Temporarily reveals the board by consuming one peek token.
  /// Does nothing when no tokens are available. The timer logic is handled by the UI.
  void peekBoard() {
    bool consumed = providerContainer
        .read(peekingProvider.notifier)
        .consumeTokenForPeek(appModel.turn);
    if (consumed) {
      updateBoard();
    }
  }

  /// Temporarily unfreezes the board during a peek in Snapshot mode.
  void startSnapshotPeek() {
    boardFrozen = false;
    snapSprites(snap: true);
    appModel.update();
  }

  /// Refreezes the board in Snapshot mode after a peek ends.
  void stopSnapshotPeek() {
    boardFrozen = true;
    appModel.update();
  }

  /// (Snapshot mode) Syncs the frozen visual board with the live engine state.
  void updateBoard() {
    boardFrozen = false;
    snapSprites(snap: true);
    // Refreeze after the single sync frame.
    Future.microtask(() {
      boardFrozen = true;
      appModel.update();
    });
  }

  // ── AI ──

  void _aiMove() async {
    if (appModel.gameOver) return;

    // Falls der Server gerade aufwärmt, warten wir mit der Zuganfrage,
    // bis er wach ist (oder der Aufwärm-Timer abgelaufen ist).
    if (appModel.playerCount == 1 &&
        !appModel.isServerAwake &&
        appModel.isServerWarmingUp) {
      while (!appModel.isServerAwake && appModel.isServerWarmingUp) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (appModel.gameOver ||
            !appModel.isAIsTurn ||
            appModel.historyViewIndex != null) return;
      }
    }

    final int difficulty = appModel.aiDifficulty;

    // FEN generieren
    final chess = ChessState();
    for (var mso in board.moveStack) {
      chess.makeMove(StockfishService.msoToUCI(mso));
    }
    final fen = chess.fen;

    // Bot ID generieren
    final botSettings =
        providerContainer.read(botSettingsNotifierProvider).value ??
            BotSettings();
    final request = MoveRequest(
      fen: fen,
      elo: botSettings.elo,
      character: botSettings.character,
    );

    aiOperation = CancelableOperation.fromFuture(
      _aiService.getBotMove(request),
    );

    aiOperation?.value.then((response) {
      if (appModel.gameOver ||
          !appModel.isAIsTurn ||
          appModel.historyViewIndex != null) return;
      if (response == null) return;

      final move = _uciToMove((response as MoveResponse).move);

      validMoves = [];
      var meta = board.push(move, getMeta: true);
      appModel.audio.playMovedSound();
      _moveCompletion(meta, changeTurn: !meta.promotion);
      if (meta.promotion) {
        appModel.moveMetaList.last.promotionType = move.promotionType;
        _moveCompletion(appModel.moveMetaList.last, updateMetaList: false);
      }
    }).catchError((e) {
      debugPrint(
          '[AI] Remote API failed ($e). Falling back to local Stockfish.');
      // Backend not reachable — fall back to local Stockfish seamlessly.
      _aiMoveFallback(difficulty);
    });
  }

  /// Fallback: uses the bundled Stockfish binary when the remote API is unreachable.
  void _aiMoveFallback(int difficulty) {
    if (appModel.gameOver ||
        !appModel.isAIsTurn ||
        appModel.historyViewIndex != null) return;
    final movesStr =
        board.moveStack.map((mso) => StockfishService.msoToUCI(mso)).join(' ');
    aiOperation = CancelableOperation.fromFuture(
      StockfishService.instance.getBestMove(movesStr, difficulty),
    );
    aiOperation?.value.then((move) {
      if (move == null ||
          (move.from == 0 && move.to == 0) ||
          appModel.gameOver) {
        appModel.endGame();
      } else {
        validMoves = [];
        var meta = board.push(move, getMeta: true);
        appModel.audio.playMovedSound();
        _moveCompletion(meta, changeTurn: !meta.promotion);
        if (meta.promotion) {
          appModel.moveMetaList.last.promotionType = move.promotionType;
          _moveCompletion(appModel.moveMetaList.last, updateMetaList: false);
        }
      }
    });
  }

  Move _uciToMove(String uci) {
    if (uci == 'e1g1') return Move(60, 63);
    if (uci == 'e1c1') return Move(60, 56);
    if (uci == 'e8g8') return Move(4, 7);
    if (uci == 'e8c8') return Move(4, 0);

    int fromFile = uci.codeUnitAt(0) - 97;
    int fromRank = 8 - int.parse(uci[1]);
    int toFile = uci.codeUnitAt(2) - 97;
    int toRank = 8 - int.parse(uci[3]);

    Move move = Move(fromRank * 8 + fromFile, toRank * 8 + toFile);

    if (uci.length > 4) {
      switch (uci[4]) {
        case 'q':
          move.promotionType = ChessPieceType.queen;
          break;
        case 'r':
          move.promotionType = ChessPieceType.rook;
          break;
        case 'b':
          move.promotionType = ChessPieceType.bishop;
          break;
        case 'n':
          move.promotionType = ChessPieceType.knight;
          break;
      }
    }
    return move;
  }

  void cancelAIMove() {
    aiOperation?.cancel();
  }

  void triggerAIMove() {
    _aiMove();
  }

  // ── Undo / Redo ──

  void undoMove() {
    appModel.haptic.light();
    board.redoStack.add(board.pop());
    if (appModel.moveMetaList.length > 1) {
      var meta = appModel.moveMetaList[appModel.moveMetaList.length - 2];
      _moveCompletion(meta, clearRedo: false, undoing: true);
    } else {
      _undoOpeningMove();
      appModel.changeTurn();
    }
  }

  void undoTwoMoves() {
    appModel.haptic.light();
    board.redoStack.add(board.pop());
    board.redoStack.add(board.pop());
    appModel.popMoveMeta();
    if (appModel.moveMetaList.length > 1) {
      _moveCompletion(appModel.moveMetaList[appModel.moveMetaList.length - 2],
          clearRedo: false, undoing: true, changeTurn: false);
    } else {
      _undoOpeningMove();
    }
  }

  void _undoOpeningMove() {
    selectedPiece = null;
    validMoves = [];
    latestMove = null;
    checkHintTile = null;
    warningTile = null;
    appModel.popMoveMeta();
  }

  void redoMove() {
    appModel.haptic.light();
    _moveCompletion(board.pushMSO(board.redoStack.removeLast()),
        clearRedo: false);
  }

  void redoTwoMoves() {
    appModel.haptic.light();
    _moveCompletion(board.pushMSO(board.redoStack.removeLast()),
        clearRedo: false, updateMetaList: true);
    _moveCompletion(board.pushMSO(board.redoStack.removeLast()),
        clearRedo: false, updateMetaList: true);
  }

  // ── Promotion ──

  void promote(ChessPieceType type) {
    board.moveStack.last.movedPiece?.type = type;
    board.moveStack.last.promotionType = type;
    board.addPromotedPiece(board.moveStack.last);
    appModel.moveMetaList.last.promotionType = type;
    // Play Games: pawn promotion achievement (human player only)
    if (!appModel.isAIsTurn) {
      PlayGamesService.instance.onPawnPromotion();
    }
    _moveCompletion(appModel.moveMetaList.last, updateMetaList: false);
  }

  // ── Move Completion ──

  void _moveCompletion(
    MoveMeta meta, {
    bool clearRedo = true,
    bool undoing = false,
    bool changeTurn = true,
    bool updateMetaList = true,
  }) async {
    if (clearRedo) {
      board.redoStack = [];
    }
    validMoves = [];
    latestMove = meta.move;
    checkHintTile = null;
    warningTile = null;
    var oppositeTurn = oppositePlayer(appModel.turn);

    // kingInCheck is lightweight (no push/pop), keep synchronous.
    if (board.kingInCheck(oppositeTurn)) {
      meta.isCheck = true;
      checkHintTile = board.kingForPlayer(oppositeTurn)?.tile;
      // Play Games: put opponent in check (human player's move only)
      if (!appModel.isAIsTurn) {
        PlayGamesService.instance.onCheckDelivered();
      }
    }

    // Capture the mover's player BEFORE changeTurn() so endGame() can
    // determine the winner correctly even after the turn has been flipped.
    // (Bug fix: endGame() uses `turn` to decide win/lose audio — if we call
    // it after changeTurn() the wrong player is reported as the winner.)
    final Player moverTurn = appModel.turn;

    // Apply all non-checkmate state changes and trigger a rebuild immediately
    // so the move animation plays without waiting for the isolate.
    if (undoing) {
      appModel.popMoveMeta(silent: true);
      appModel.undoEndGame(silent: true);
    } else if (updateMetaList) {
      appModel.pushMoveMeta(meta, silent: true);
    }
    if (changeTurn) {
      if (!undoing && appModel.timerMode == 'increment') {
        appModel.timerService
            .addIncrement(appModel.turn, appModel.timerIncrement);
      }
      appModel.changeTurn(silent: true);
    }
    selectedPiece = null;
    // First rebuild — shows the move immediately without blocking on checkmate.
    appModel.update();

    // Offload kingInCheckmate to the persistent background isolate so the UI
    // thread is free to render the move animation.
    final snapshot = serializeBoardForCheckmate(board, oppositeTurn);
    // Fall back to compute() if the worker hasn't finished initialising yet
    // (only possible on the very first move of the very first game).
    final bool isCheckmate = _checkmateWorker != null
        ? await _checkmateWorker!.check(snapshot)
        : checkmateIsolateEntry(snapshot);

    // Guard: the game may have ended for another reason (e.g. timer) while the
    // isolate was running — skip applying a stale result.
    if (appModel.gameOver && !isCheckmate) {
      if (appModel.isAIsTurn && !undoing && changeTurn) {
        _aiMove();
      }
      return;
    }

    if (isCheckmate) {
      if (!meta.isCheck) {
        appModel.stalemate = true;
        meta.isStalemate = true;
      }
      meta.isCheck = false;
      meta.isCheckmate = true;
      // Pass moverTurn so endGame() sees the winner, not the post-changeTurn
      // loser. endGame() compares this against playerSide to play win/lose audio.
      appModel.endGame(silent: true, winner: moverTurn);
      appModel.update();
    }

    // Trigger haptic feedback based on move outcome
    final isOpponentMove =
        appModel.playingWithAI && (meta.player != appModel.playerSide);

    if (meta.isCheckmate) {
      appModel.haptic.vibrate();
    } else if (meta.isStalemate) {
      appModel.haptic.heavy();
    } else if (isOpponentMove) {
      if (meta.isCheck) {
        appModel.haptic.medium();
      } else {
        appModel.haptic.light();
      }
    } else {
      // Human move
      if (meta.isCheck) {
        appModel.haptic.heavy();
      } else if (meta.took) {
        appModel.haptic.medium();
      } else if (meta.kingCastle || meta.queenCastle) {
        appModel.haptic.doubleLight();
      } else {
        appModel.haptic.light();
      }
    }

    // Trigger AI if it's now the AI's turn. Use !undoing instead of clearRedo
    // so that undoing the human's last move (which restores AI's turn) still
    // calls _aiMove(), preventing the AI from freezing after an undo-to-AI-turn.
    if (appModel.isAIsTurn && !undoing && changeTurn) {
      _aiMove();
    }

    if (!undoing) {
      final isPendingPromotion =
          meta.promotion && !changeTurn && meta.player == appModel.playerSide;
      if (!isPendingPromotion) {
        final isAiMove =
            appModel.playingWithAI && meta.player != appModel.playerSide;
        if (isAiMove) {
          final elapsed = _userMoveTime != null
              ? DateTime.now().difference(_userMoveTime!).inMilliseconds
              : 1000;
          final delay = math.max(0, 1000 - elapsed);
          Future.delayed(Duration(milliseconds: delay), () {
            appModel.speak("Opponent played ${_formatMoveSpokenText(meta)}");
          });
        } else {
          appModel.speak(_formatMoveSpokenText(meta));
          if (appModel.playingWithAI) {
            _userMoveTime = DateTime.now();
          }
        }
      }
    }
  }

  void snapSprites({bool snap = true}) {
    onSnapSprites?.call(snap: snap);
  }

  /// Releases the background checkmate isolate. Call when discarding this
  /// controller (e.g. on new game or app dispose).
  void dispose() {
    _checkmateWorker?.dispose();
    _checkmateWorker = null;
  }

  String _tileToSquare(int tile) {
    final col = tile % 8;
    final row = (tile / 8).floor();
    final f = String.fromCharCode('a'.codeUnitAt(0) + col);
    final r = (8 - row).toString();
    return '$f$r';
  }

  String _formatMoveSpokenText(MoveMeta meta) {
    if (meta.kingCastle) return 'Castle King-side';
    if (meta.queenCastle) return 'Castle Queen-side';

    String pieceName = '';
    switch (meta.type) {
      case ChessPieceType.king:
        pieceName = 'King';
        break;
      case ChessPieceType.queen:
        pieceName = 'Queen';
        break;
      case ChessPieceType.rook:
        pieceName = 'Rook';
        break;
      case ChessPieceType.bishop:
        pieceName = 'Bishop';
        break;
      case ChessPieceType.knight:
        pieceName = 'Knight';
        break;
      case ChessPieceType.pawn:
        pieceName = 'Pawn';
        break;
      default:
        break;
    }

    final toSq = _tileToSquare(meta.move?.to ?? 0);

    String text = '';
    final action = meta.took ? 'takes' : 'to';
    if (pieceName == 'Pawn') {
      if (meta.took) {
        final fromCol = meta.move?.from != null ? meta.move!.from % 8 : 0;
        final fromF = String.fromCharCode('a'.codeUnitAt(0) + fromCol);
        text = '$fromF takes ${toSq.toUpperCase()}';
      } else {
        text = 'Pawn to ${toSq.toUpperCase()}';
      }
    } else {
      text = '$pieceName $action ${toSq.toUpperCase()}';
    }

    if (meta.promotion) {
      String promoPiece = 'Queen';
      switch (meta.promotionType) {
        case ChessPieceType.queen:
          promoPiece = 'Queen';
          break;
        case ChessPieceType.rook:
          promoPiece = 'Rook';
          break;
        case ChessPieceType.bishop:
          promoPiece = 'Bishop';
          break;
        case ChessPieceType.knight:
          promoPiece = 'Knight';
          break;
        default:
          break;
      }
      text += ', promoting to $promoPiece';
    }

    if (meta.isCheckmate && !meta.isStalemate) {
      text += ', checkmate';
    } else if (meta.isCheck) {
      text += ', check';
    }

    return text;
  }
}
