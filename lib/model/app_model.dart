import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logic/audio_service.dart';
import '../logic/chess_piece.dart';
import '../logic/game_controller.dart';
import '../logic/game_history_storage.dart';
import '../logic/game_mode_notifier.dart';
import '../logic/game_state_storage.dart';
import '../logic/haptic_service.dart';
import '../logic/move_calculation/move_classes/move.dart';
import '../logic/move_calculation/move_classes/move_meta.dart';
import '../logic/move_calculation/move_classes/move_stack_object.dart';
import '../logic/play_games_service.dart';
import '../logic/remote_ai_service.dart';
import '../logic/shared_functions.dart';
import '../logic/stockfish_service.dart';
import '../logic/timer_service.dart';
import '../logic/tts_service.dart';
import 'app_themes.dart';
import 'completed_game.dart';
import 'game_state.dart';
import 'player.dart';
import 'user_preferences.dart';

class AppModel extends ChangeNotifier {
  // ── Game Settings ──
  int playerCount = 1;
  int aiDifficulty = 1;
  Player selectedSide = Player.player1;
  Player playerSide = Player.player1;
  ChessMode gameMode = ChessMode.normal;
  bool isAnalysisMode = false;
  bool _hasSavedGame = false;
  bool get hasSavedGame => _hasSavedGame;

  Future<void> checkSavedGame() async {
    _hasSavedGame = await GameStateStorage.hasSavedGame();
    notifyListeners();
  }

  /// The side Player 1 chooses to start on in a 2-player game.
  Player selectedSideP1 = Player.player1;

  // ── Services ──
  final UserPreferences prefs;
  final AudioService audio = AudioService();
  final TimerService timerService = TimerService();
  final HapticService haptic = HapticService();
  final TTSService tts = TTSService();

  // ── Delegated Accessors (backward compatibility) ──
  int get timeLimit => timerService.timeLimit;
  String get pieceTheme => prefs.pieceTheme;
  String get themeName => prefs.themeName;
  bool get showMoveHistory => prefs.showMoveHistory;
  bool get allowUndoRedo => prefs.allowUndoRedo;
  bool get soundEnabled => prefs.soundEnabled;
  bool get showHints => prefs.showHints;
  bool get showNotation => prefs.showNotation;
  bool get enableRotation => prefs.enableRotation;
  bool get enablePieceRotation => prefs.enablePieceRotation;
  bool get hapticEnabled => prefs.hapticEnabled;
  String get aiEngine => prefs.aiEngine;
  int get timerIncrement => prefs.timerIncrement;
  String get timerMode => prefs.timerMode;
  AppTheme get theme => prefs.theme;
  int get themeIndex => prefs.themeIndex;
  int get pieceThemeIndex => prefs.pieceThemeIndex;
  List<String> get pieceThemes => prefs.pieceThemes;

  bool get ttsEnabled => prefs.ttsEnabled;
  double get ttsSpeechRate => prefs.ttsSpeechRate;
  double get ttsPitch => prefs.ttsPitch;

  // ── Navigation ──
  int navIndex = 0;
  void setNavIndex(int index) {
    navIndex = index;
    notifyListeners();
  }

  // ── Linked Accounts (Analysis feature) ──
  String get lichessUsername => prefs.lichessUsername;
  String get chessComUsername => prefs.chessComUsername;
  bool get hasLinkedAccounts =>
      prefs.lichessUsername.isNotEmpty || prefs.chessComUsername.isNotEmpty;

  Future<void> setLichessUsername(String name) async {
    await prefs.setLichessUsername(name);
    notifyListeners();
  }

  Future<void> setChessComUsername(String name) async {
    await prefs.setChessComUsername(name);
    notifyListeners();
  }

  Future<void> setTtsEnabled(bool enabled) async {
    debugPrint('[AppModel] setTtsEnabled($enabled) called');
    await prefs.setTtsEnabled(enabled);
    debugPrint(
        '[AppModel] setTtsEnabled($enabled) persisted — prefs.ttsEnabled=${prefs.ttsEnabled}');
    notifyListeners();
  }

  Future<void> setTtsSpeechRate(double rate) async {
    await prefs.setTtsSpeechRate(rate);
    notifyListeners();
  }

  Future<void> setTtsPitch(double pitch) async {
    await prefs.setTtsPitch(pitch);
    notifyListeners();
  }

  void speak(String text) {
    debugPrint(
        '[AppModel] speak("$text") mode=$gameMode ttsEnabled=$ttsEnabled');
    if (gameMode == ChessMode.blind || gameMode == ChessMode.snapshot) {
      tts.speak(text,
          enabled: ttsEnabled, rate: ttsSpeechRate, pitch: ttsPitch);
    }
  }

  // ── Profile / Stats Accessors ──
  int get userRatingNormal => prefs.userRatingNormal;
  int get userRatingBlind => prefs.userRatingBlind;
  List<int> get beatenBots => prefs.beatenBots;
  List<int> get beatenBotsBlind => prefs.beatenBotsBlind;
  String get userName => prefs.userName;

  String get userAvatar => prefs.userAvatar;

  int get lastGameRatingChangeNormal => prefs.lastGameRatingChangeNormal;
  int get lastGameRatingChangeBlind => prefs.lastGameRatingChangeBlind;
  String get lastGameDateNormal => prefs.lastGameDateNormal;
  String get lastGameDateBlind => prefs.lastGameDateBlind;
  int get todayRatingChangeNormal => prefs.todayRatingChangeNormal;
  int get todayRatingChangeBlind => prefs.todayRatingChangeBlind;

  // Active getters (for backward compatibility where applicable)
  int get userRating =>
      gameMode == ChessMode.blind || gameMode == ChessMode.snapshot
          ? userRatingBlind
          : userRatingNormal;
  int get lastGameRatingChange =>
      gameMode == ChessMode.blind || gameMode == ChessMode.snapshot
          ? lastGameRatingChangeBlind
          : lastGameRatingChangeNormal;
  String get lastGameDate =>
      gameMode == ChessMode.blind || gameMode == ChessMode.snapshot
          ? lastGameDateBlind
          : lastGameDateNormal;
  int get todayRatingChange =>
      gameMode == ChessMode.blind || gameMode == ChessMode.snapshot
          ? todayRatingChangeBlind
          : todayRatingChangeNormal;

  int getRatingAdjustmentsCount(bool isBlind) {
    final count = isBlind
        ? prefs.ratingAdjustmentsCountBlind
        : prefs.ratingAdjustmentsCountNormal;
    final timestamp = isBlind
        ? prefs.lastAdjustmentTimestampBlind
        : prefs.lastAdjustmentTimestampNormal;
    if (count >= 2) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final timePassed = now - timestamp;
      const sixtyDaysMs = 60 * 24 * 60 * 60 * 1000;
      if (timePassed >= sixtyDaysMs) {
        // Cooldown expired! Reset count.
        prefs.resetRatingAdjustmentsCount(isBlind);
        return 0;
      }
    }
    return count;
  }

  bool isRatingAdjustmentLocked(bool isBlind) =>
      getRatingAdjustmentsCount(isBlind) >= 2;

  int getRatingAdjustmentCooldownDaysLeft(bool isBlind) {
    if (getRatingAdjustmentsCount(isBlind) < 2) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final timestamp = isBlind
        ? prefs.lastAdjustmentTimestampBlind
        : prefs.lastAdjustmentTimestampNormal;
    final timePassed = now - timestamp;
    const sixtyDaysMs = 60 * 24 * 60 * 60 * 1000;
    final remainingMs = sixtyDaysMs - timePassed;
    if (remainingMs <= 0) return 0;
    return (remainingMs / (24 * 60 * 60 * 1000)).ceil();
  }

  Future<void> adjustUserRating(int rating, bool isBlind) async {
    await prefs.adjustUserRating(rating, isBlind);
    notifyListeners();
  }

  Future<void> setUserName(String name) async {
    await prefs.setUserName(name);
    notifyListeners();
  }

  Future<void> setUserAvatar(String avatar) async {
    await prefs.setUserAvatar(avatar);
    notifyListeners();
  }

  Future<void> resetStats() async {
    await prefs.resetStats();
    notifyListeners();
  }

  ValueNotifier<Duration> get player1TimeLeft => timerService.player1TimeLeft;
  set player1TimeLeft(ValueNotifier<Duration> val) =>
      timerService.player1TimeLeft.value = val.value;
  ValueNotifier<Duration> get player2TimeLeft => timerService.player2TimeLeft;
  set player2TimeLeft(ValueNotifier<Duration> val) =>
      timerService.player2TimeLeft.value = val.value;

  // ── Game State (Model) ──
  /// Pure game-outcome data, separated from ViewModel concerns.
  /// Access via the proxy getters below; do not reach into [_gameState] directly
  /// from outside this class.
  final GameState _gameState = GameState();

  // Proxy getters/setters — all external code reads appModel.gameOver etc.
  // as before; we just delegate to the model layer now.
  bool get gameOver => _gameState.gameOver;
  set gameOver(bool v) => _gameState.gameOver = v;
  bool get stalemate => _gameState.stalemate;
  set stalemate(bool v) => _gameState.stalemate = v;
  bool get userWon => _gameState.userWon;
  set userWon(bool v) => _gameState.userWon = v;
  Player get turn => _gameState.turn;
  set turn(Player v) => _gameState.turn = v;
  List<MoveMeta> get moveMetaList => _gameState.moveMetaList;
  set moveMetaList(List<MoveMeta> v) => _gameState.moveMetaList = v;

  // ── ViewModel-layer game state ──
  GameController? gameController;
  bool promotionRequested = false;
  bool moveListUpdated = false;
  int? historyViewIndex;
  final List<MoveStackObject> historyRedoStack = [];
  Timer? _historyAnimationTimer;

  /// Set to true once the essential piece-image assets have finished decoding
  /// after runApp(). Until then, navigation to ChessView is disabled.
  bool imagesReady = false;

  // ── Computed Properties ──
  Player get aiTurn => oppositePlayer(playerSide);
  bool get isAIsTurn =>
      playingWithAI && (turn == aiTurn) && (historyViewIndex == null);
  bool get playingWithAI => playerCount == 1;

  // ── Save Debounce ──
  Timer? _saveDebounceTimer;

  // ── Server Warmup State ──
  bool isServerWarmingUp = false;
  bool isServerAwake = false;
  int serverWarmUpSecondsLeft = 50;
  Timer? _warmUpTimer;
  Timer? _pingPollTimer;

  Future<void> startServerWarmup() async {
    if (isServerAwake || isServerWarmingUp) return;

    final aiService = providerContainer.read(remoteAiServiceProvider);

    // Initialer schneller Check: Wenn der Server bereits wach ist,
    // beenden wir das Aufwärmen sofort und überspringen den Countdown komplett.
    final quickSuccess = await aiService.pingServer();
    if (quickSuccess) {
      isServerAwake = true;
      isServerWarmingUp = false;
      serverWarmUpSecondsLeft = 0;
      notifyListeners();
      return;
    }

    // Falls der Server schläft, starten wir den Countdown und das periodische Pollen
    isServerWarmingUp = true;
    serverWarmUpSecondsLeft = 50;
    notifyListeners();

    // Start countdown timer
    _warmUpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (serverWarmUpSecondsLeft > 0) {
        serverWarmUpSecondsLeft--;
        notifyListeners();
      } else {
        timer.cancel();
        isServerWarmingUp = false;
        notifyListeners();
      }
    });

    // Periodically poll /health
    _pingPollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final success = await aiService.pingServer();
      if (success) {
        timer.cancel();
        _warmUpTimer?.cancel();
        isServerAwake = true;
        isServerWarmingUp = false;
        serverWarmUpSecondsLeft = 0;
        notifyListeners();
      }
    });
  }

  // ── Undo Bank ──
  /// Number of free undos remaining for the current game.
  /// Starts at 1 for each new game. Players can earn 1 more by watching an ad.
  int _availableUndos = 1;
  int get availableUndos => _availableUndos;

  void resetUndos() {
    _availableUndos = 1;
    notifyListeners();
  }

  void decrementUndo() {
    if (_availableUndos > 0) {
      _availableUndos--;
      notifyListeners();
    }
  }

  void grantUndoFromAd() {
    _availableUndos++;
    notifyListeners();
  }

  // Used to prevent AnimatedRotation from sweeping across the screen when first loading the board.
  bool animateBoardRotation = false;
  bool? _gameOverInvertedState;

  bool get isBoardInverted {
    if (historyViewIndex != null || isAnalysisMode) {
      return playerSide == Player.player2;
    }
    if (_gameOverInvertedState != null && gameOver) {
      return _gameOverInvertedState!;
    }
    if (playingWithAI) {
      return playerSide == Player.player2;
    } else {
      return enableRotation && turn == Player.player2;
    }
  }

  AppModel({UserPreferences? prefs, bool skipServerWarmup = false}) : prefs = prefs ?? UserPreferences() {
    // Wire up service callbacks
    this.prefs.onChanged = () {
      audio.enabled = this.prefs.soundEnabled;
      haptic.enabled = this.prefs.hapticEnabled;
      notifyListeners();
    };
    tts.init();
    timerService.onExpired = () => endGame();
    audio.enabled = this.prefs.soundEnabled;
    audio.initialize();
    haptic.enabled = this.prefs.hapticEnabled;

    if (prefs == null) {
      this.prefs.load();
    }

    // Start warming up the Render cloud server in the background
    if (!skipServerWarmup) {
      startServerWarmup();
    }
    checkSavedGame();
  }

  // ── Game Lifecycle ──

  void newGame({bool notify = true, ChessMode mode = ChessMode.normal}) {
    gameMode = mode;
    gameController?.cancelAIMove();
    timerService.stop();
    GameStateStorage.clearGameState();
    _hasSavedGame = false;

    _gameOverInvertedState = null;
    _gameState.reset(); // reset all pure-model game state in one call
    promotionRequested = false;
    moveListUpdated = false;
    historyViewIndex = null;
    historyRedoStack.clear();
    _historyAnimationTimer?.cancel();
    timerService.configure(timeLimit,
        incrementSeconds: timerIncrement, mode: timerMode);
    audio.enabled = prefs.soundEnabled;
    // Reset undo bank for the new game.
    _availableUndos = 1;
    if (selectedSide == Player.random) {
      playerSide = math.Random.secure().nextInt(2) == 0
          ? Player.player1
          : Player.player2;
    } else {
      playerSide = selectedSide;
    }

    // In a 2-player game, let Player 1 start on their chosen side.
    if (!playingWithAI) {
      if (selectedSideP1 == Player.random) {
        playerSide = math.Random.secure().nextInt(2) == 0
            ? Player.player1
            : Player.player2;
      } else {
        playerSide = selectedSideP1;
      }
    }
    // Dispose the previous controller's background isolate before replacing it.
    gameController?.dispose();
    gameController = GameController(this);
    timerService.start(() => turn, () => gameOver);

    // Trigger AI move if it's AI's turn natively for standard games
    if (isAIsTurn && !gameOver) {
      gameController!.triggerAIMove();
    }

    // Play Games: track game start and unlock milestone achievements
    PlayGamesService.instance.onGameStarted();

    // Disable animation on load, then enable it after the board is rendered.
    animateBoardRotation = false;
    Future.delayed(Duration(milliseconds: 50), () {
      animateBoardRotation = true;
      notifyListeners();
    });

    if (notify) {
      notifyListeners();
    }

    if (mode == ChessMode.blind || mode == ChessMode.snapshot) {
      speak(
          "Game started, you are playing as ${playerSide == Player.player1 ? 'White' : 'Black'}.");
    }
  }

  void exitChessView() {
    gameController?.cancelAIMove();
    timerService.stop();
    GameStateStorage.clearGameState();
    _hasSavedGame = false;
    historyViewIndex = null;
    notifyListeners();
  }

  void saveAndExitChessView() {
    if (historyViewIndex != null) {
      setHistoryViewIndex(null, snap: true, playAudio: false);
    }
    saveGameState();
    gameController?.cancelAIMove();
    timerService.stop();
    notifyListeners();
  }

  // ── Move State Management ──

  void pushMoveMeta(MoveMeta meta, {bool silent = false}) {
    moveMetaList.add(meta);
    moveListUpdated = true;
    if (!silent) notifyListeners();
    saveGameState();
  }

  void popMoveMeta({bool silent = false}) {
    moveMetaList.removeLast();
    moveListUpdated = true;
    if (!silent) notifyListeners();
    saveGameState();
  }

  void setHistoryViewIndex(int? index,
      {int? visualIndex,
      bool snap = true,
      bool playAudio = false,
      bool showLatestMoveHighlight = true}) {
    if (gameController == null) return;
    _historyAnimationTimer?.cancel();

    // Clear any selection/hints on history navigation.
    gameController!.selectedPiece = null;
    gameController!.validMoves = const [];
    gameController!.warningTile = null;

    // If returning to current live state (latest move or null)
    if (index == null || index == moveMetaList.length - 1) {
      while (historyRedoStack.isNotEmpty) {
        gameController!.board.pushMSO(historyRedoStack.removeLast());
      }
      historyViewIndex = null;
      moveListUpdated = true;
      if (moveMetaList.isNotEmpty) {
        gameController!.latestMove = moveMetaList.last.move;
      } else {
        gameController!.latestMove = null;
      }
      if (!gameOver) {
        timerService.resume();
        if (isAIsTurn) {
          gameController!.triggerAIMove();
        }
      }
      if (playAudio) {
        audio.playMovedSound();
      }
      gameController!.snapSprites(snap: snap);
      notifyListeners();
      return;
    }

    // Do not pause game during review
    gameController?.cancelAIMove();

    int targetLength = index + 1;
    if (gameController!.board.moveStack.length > targetLength) {
      while (gameController!.board.moveStack.length > targetLength) {
        historyRedoStack.add(gameController!.board.pop());
      }
    } else if (gameController!.board.moveStack.length < targetLength) {
      while (gameController!.board.moveStack.length < targetLength &&
          historyRedoStack.isNotEmpty) {
        gameController!.board.pushMSO(historyRedoStack.removeLast());
      }
    }

    historyViewIndex = visualIndex ?? index;
    if (index >= 0 && index < moveMetaList.length) {
      if (showLatestMoveHighlight) {
        gameController!.latestMove = moveMetaList[index].move;
      } else {
        gameController!.latestMove = null;
      }
    } else {
      gameController!.latestMove = null;
    }
    if (playAudio) {
      audio.playMovedSound();
    }
    gameController!.snapSprites(snap: snap);
    notifyListeners();
  }

  void selectHistoryTurn(int turnIndex) {
    _historyAnimationTimer?.cancel();

    final int whiteMoveIndex = turnIndex * 2;
    final int? blackMoveIndex =
        (turnIndex * 2 + 1 < moveMetaList.length) ? (turnIndex * 2 + 1) : null;

    // 1. Instantly snap to the position before White's move (index - 1, or -1 for the very start)
    // Pass visualIndex: whiteMoveIndex so that the UI immediately highlights the selected turn tile.
    // Set showLatestMoveHighlight: false so the board does not show the previous turn's highlight squares.
    final int beforeWhiteIndex = whiteMoveIndex > 0 ? (whiteMoveIndex - 1) : -1;
    setHistoryViewIndex(beforeWhiteIndex,
        visualIndex: whiteMoveIndex,
        snap: true,
        playAudio: false,
        showLatestMoveHighlight: false);

    // 2. Schedule White's move to play with animation (snap = false) after a brief frame delay
    _historyAnimationTimer = Timer(const Duration(milliseconds: 250), () {
      setHistoryViewIndex(whiteMoveIndex,
          visualIndex: whiteMoveIndex, snap: false, playAudio: true);

      // 3. Schedule Black's move to play after the White move finishes sliding
      if (blackMoveIndex != null) {
        _historyAnimationTimer = Timer(const Duration(milliseconds: 600), () {
          setHistoryViewIndex(blackMoveIndex,
              visualIndex: blackMoveIndex, snap: false, playAudio: true);
        });
      }
    });
  }

  void endGame({bool silent = false, Player? winner}) {
    if (gameOver) return;
    _gameOverInvertedState = isBoardInverted;
    gameOver = true;

    final actualWinner = winner ?? turn;

    if (gameController != null) {
      final moves = gameController!.board.moveStack
          .map((mso) => Move(mso.move.from, mso.move.to,
              promotionType: mso.promotionType ?? ChessPieceType.promotion))
          .toList();
      GameHistoryStorage.saveGame(CompletedGame(
        date: DateTime.now(),
        winner: actualWinner,
        stalemate: stalemate,
        aiDifficulty: aiDifficulty,
        moves: moves,
        playerCount: playerCount,
        playerSide: playerSide,
      ));
    }

    userWon = audio.didUserWin(
      playingWithAI: playingWithAI,
      playerSide: playerSide,
      turn: actualWinner,
      player1TimeLeft: player1TimeLeft.value,
      player2TimeLeft: player2TimeLeft.value,
    );

    audio.playGameEndSound(
      stalemate: stalemate,
      playingWithAI: playingWithAI,
      playerSide: playerSide,
      turn: actualWinner,
      player1TimeLeft: player1TimeLeft.value,
      player2TimeLeft: player2TimeLeft.value,
    );

    // Play Games: unlock win achievements
    if (userWon && playingWithAI) {
      PlayGamesService.instance.onPlayerWon(
        aiDifficulty: aiDifficulty,
        timeLimit: timeLimit,
      );
    }

    // ── Elo rating update (AI games only) ──
    if (playingWithAI) {
      // Map difficulty level (or custom ELO) to ELO rating.
      final botElo = getDifficultyElo(aiDifficulty);
      final isBlind =
          gameMode == ChessMode.blind || gameMode == ChessMode.snapshot;
      final currentRating =
          isBlind ? prefs.userRatingBlind : prefs.userRatingNormal;

      // Standard Elo expected score.
      final expected =
          1.0 / (1.0 + math.pow(10.0, (botElo - currentRating) / 400.0));

      // Score: 1 = win, 0.5 = draw (stalemate), 0 = loss.
      final score = userWon ? 1.0 : (stalemate ? 0.5 : 0.0);
      final newRating =
          (currentRating + 32 * (score - expected)).round().clamp(100, 3200);

      prefs.setUserRating(newRating, isBlind);

      // Track beaten bots.
      if (userWon && !stalemate) {
        if (isBlind) {
          prefs.addBeatenBotBlind(aiDifficulty);
        } else {
          prefs.addBeatenBot(aiDifficulty);
        }
      }
    }

    GameStateStorage.clearGameState();
    _hasSavedGame = false;
    if (!silent) notifyListeners();
  }

  void undoEndGame({bool silent = false}) {
    gameOver = false;
    stalemate = false;
    userWon = false;
    _gameOverInvertedState = null;
    if (!silent) notifyListeners();
  }

  void changeTurn({bool silent = false}) {
    turn = oppositePlayer(turn);
    if (!silent) notifyListeners();
  }

  void requestPromotion() {
    promotionRequested = true;
    notifyListeners();
  }

  // ── Game Options ──

  void setPlayerCount(int? count) {
    if (count != null) {
      haptic.light();
      playerCount = count;
      notifyListeners();
    }
  }

  void setAIDifficulty(int? difficulty) {
    if (difficulty != null) {
      haptic.light();
      aiDifficulty = difficulty;
      notifyListeners();
    }
  }

  static int getDifficultyElo(int level) {
    // If value > 5, it is already a direct ELO (custom difficulty).
    if (level > 5) return level;
    switch (level) {
      case 1:
        return 400;
      case 2:
        return 800;
      case 3:
        return 1200;
      case 4:
        return 1600;
      case 5:
        return 2000;
      default:
        return 1200;
    }
  }

  void setPlayerSide(Player? side) {
    if (side != null) {
      haptic.light();
      selectedSide = side;
      if (side != Player.random) {
        playerSide = side;
      }
      notifyListeners();
    }
  }

  void setPlayerSideP1(Player? side) {
    if (side != null) {
      haptic.light();
      selectedSideP1 = side;
      notifyListeners();
    }
  }

  void setTimeLimit(int? duration) {
    if (duration != null) {
      haptic.light();
      timerService.configure(duration);
      notifyListeners();
    }
  }

  // ── Preference Delegation ──

  void setTheme(int index) {
    haptic.light();
    prefs.setTheme(index);
  }

  void setPieceTheme(int index) {
    haptic.light();
    prefs.setPieceTheme(index);
  }

  void setShowMoveHistory(bool show) {
    haptic.light();
    prefs.setShowMoveHistory(show);
  }

  void setSoundEnabled(bool enabled) {
    haptic.light();
    prefs.setSoundEnabled(enabled);
    audio.enabled = enabled;
  }

  void setShowHints(bool show) {
    haptic.light();
    prefs.setShowHints(show);
  }

  void setShowNotation(bool show) {
    haptic.light();
    prefs.setShowNotation(show);
  }

  void setEnableRotation(bool enable) {
    haptic.light();
    prefs.setEnableRotation(enable);
  }

  void setEnablePieceRotation(bool enable) {
    haptic.light();
    prefs.setEnablePieceRotation(enable);
  }

  void setAllowUndoRedo(bool allow) {
    haptic.light();
    prefs.setAllowUndoRedo(allow);
  }

  void setHapticEnabled(bool enabled) {
    prefs.setHapticEnabled(enabled);
    haptic.enabled = enabled;
    haptic.light();
  }

  void setTimerIncrement(int increment) {
    haptic.light();
    prefs.setTimerIncrement(increment);
  }

  void setTimerMode(String mode) {
    haptic.light();
    prefs.setTimerMode(mode);
  }

  void showAchievements() => PlayGamesService.instance.showAchievements();

  Future<void> resetSettingsToDefaults() async {
    await prefs.resetToDefaults();
    audio.enabled = prefs.soundEnabled;
    haptic.enabled = prefs.hapticEnabled;
    notifyListeners();
  }

  // ── Utilities ──

  void update() {
    notifyListeners();
  }

  /// Schedules a save after a short debounce window (400 ms).
  /// Rapid undo/redo or move bursts collapse into a single write,
  /// preventing SharedPreferences I/O on every single event.
  void saveGameState() {
    _hasSavedGame = true;
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(
      const Duration(milliseconds: 400),
      () {
        GameStateStorage.saveGameState(this);
        notifyListeners();
      },
    );
  }

  /// Immediately flushes the game state to disk, bypassing the debounce.
  /// Use this in lifecycle events (app pause, explicit exit) to ensure
  /// no data is lost.
  void saveGameStateImmediate() {
    _hasSavedGame = true;
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    GameStateStorage.saveGameState(this);
    notifyListeners();
  }

  Future<void> restoreGameState() async {
    final state = await GameStateStorage.loadGameState();
    if (state == null) return;

    gameController?.cancelAIMove();
    timerService.stop();

    playerCount = state['playerCount'] as int;
    aiDifficulty = state['aiDifficulty'] as int;
    playerSide = Player.values[state['playerSide'] as int];
    selectedSide = Player.values[state['selectedSide'] as int];
    selectedSideP1 = Player
        .values[(state['selectedSideP1'] as int?) ?? Player.player1.index];
    timerService.configure(state['timeLimit'] as int);
    gameOver = state['gameOver'] as bool;
    stalemate = state['stalemate'] as bool;
    turn = Player.player1;
    moveMetaList = [];
    historyViewIndex = null;
    historyRedoStack.clear();
    _historyAnimationTimer?.cancel();

    // Restore gameMode
    final savedModeStr = state['gameMode'] as String?;
    if (savedModeStr != null) {
      gameMode = ChessMode.values.firstWhere((e) => e.name == savedModeStr,
          orElse: () => ChessMode.normal);
    } else {
      gameMode = ChessMode.normal;
    }

    // Create a fresh game and replay all moves
    gameController?.dispose();
    gameController = GameController(this);

    final savedSnapshotMoveCount = state['snapshotMoveCount'] as int?;
    if (gameMode == ChessMode.snapshot) {
      gameController!.snapshotMoveCount = savedSnapshotMoveCount;
    }

    final moves = GameStateStorage.parseMoves(state);
    for (int i = 0; i < moves.length; i++) {
      var move = moves[i];
      var meta = gameController!.board
          .push(move, getMeta: true, promotionType: move.promotionType);
      moveMetaList.add(meta);
      turn = oppositePlayer(turn);
    }
    gameController!.snapSprites();

    // Restore timer durations
    player1TimeLeft.value =
        Duration(milliseconds: state['player1TimeLeftMs'] as int);
    player2TimeLeft.value =
        Duration(milliseconds: state['player2TimeLeftMs'] as int);

    // Restore timer increment and mode
    final savedIncrement = (state['timerIncrement'] as int?) ?? 0;
    prefs.setTimerIncrement(savedIncrement);
    final savedMode = (state['timerMode'] as String?) ?? 'increment';
    prefs.setTimerMode(savedMode);
    timerService.configure(state['timeLimit'] as int,
        incrementSeconds: savedIncrement, mode: savedMode);

    // Restore game over / stalemate state
    gameOver = state['gameOver'] as bool;
    stalemate = state['stalemate'] as bool;

    // Restore undo bank (falls back to 1 for saves predating this feature).
    _availableUndos = (state['availableUndos'] as int?) ?? 1;

    // Update visual state from last move
    if (moveMetaList.isNotEmpty) {
      gameController!.latestMove = moveMetaList.last.move;
      if (gameController!.board.kingInCheck(turn)) {
        gameController!.checkHintTile =
            gameController!.board.kingForPlayer(turn)?.tile;
      }
    }

    timerService.start(() => turn, () => gameOver);

    moveListUpdated = true;
    notifyListeners();

    // Trigger AI move if it's AI's turn
    if (isAIsTurn && !gameOver) {
      gameController!.triggerAIMove();
    }

    animateBoardRotation = false;
    Future.delayed(Duration(milliseconds: 50), () {
      animateBoardRotation = true;
      notifyListeners();
    });
  }

  void loadCompletedGame(CompletedGame game) {
    gameController?.cancelAIMove();
    timerService.stop();

    playerCount = game.playerCount;
    aiDifficulty = game.aiDifficulty;
    playerSide = game.playerSide;
    selectedSide = game.playerSide;
    gameOver = true;
    stalemate = game.stalemate;
    turn = Player.player1;
    moveMetaList = [];
    historyViewIndex = null;
    historyRedoStack.clear();
    _historyAnimationTimer?.cancel();

    gameController?.dispose();
    gameController = GameController(this);

    for (var move in game.moves) {
      var meta = gameController!.board
          .push(move, getMeta: true, promotionType: move.promotionType);
      moveMetaList.add(meta);
      turn = oppositePlayer(turn);
    }
    gameController!.snapSprites();

    _availableUndos = 0;

    if (moveMetaList.isNotEmpty) {
      gameController!.latestMove = moveMetaList.last.move;
      if (gameController!.board.kingInCheck(turn)) {
        gameController!.checkHintTile =
            gameController!.board.kingForPlayer(turn)?.tile;
      }
    }

    moveListUpdated = true;
    historyViewIndex = moveMetaList.length > 0 ? moveMetaList.length - 1 : 0;

    animateBoardRotation = false;
    Future.delayed(Duration(milliseconds: 50), () {
      animateBoardRotation = true;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _warmUpTimer?.cancel();
    _pingPollTimer?.cancel();
    gameController?.dispose();
    StockfishService.instance.dispose();
    tts.stop();
    super.dispose();
  }
}
