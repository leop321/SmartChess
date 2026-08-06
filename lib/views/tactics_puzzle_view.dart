import 'package:chess/chess.dart' as ch;
import 'package:flame/game.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/chess_game.dart';
import '../logic/game_controller.dart';
import '../logic/puzzle_providers/tactics_task_provider.dart';
import '../logic/tactics_judge.dart';
import '../logic/tactics_puzzle_controller.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/game_analysis_models.dart';
import '../model/lichess_puzzle.dart';
import '../model/player.dart';
import '../model/tactics_task.dart';
import 'components/analyze_view/game_analysis_page.dart';

class TacticsPuzzleView extends StatefulWidget {
  final TacticsMode mode;
  final TacticsTaskProvider? provider;
  final TacticsJudge? judge;

  const TacticsPuzzleView({
    Key? key,
    this.mode = TacticsMode.classic,
    this.provider,
    this.judge,
  }) : super(key: key);

  @override
  State<TacticsPuzzleView> createState() => _TacticsPuzzleViewState();
}

class _TacticsPuzzleViewState extends State<TacticsPuzzleView> {
  late TacticsPuzzleController _controller;
  late AppModel _puzzleAppModel;
  late GameController _puzzleGameController;
  ChessGame? _chessGame;

  @override
  void initState() {
    super.initState();
    final globalAppModel = context.read<AppModel>();

    // Create an ephemeral AppModel for the puzzle to avoid mutating the main offline game
    _puzzleAppModel = AppModel();
    _puzzleAppModel.prefs.themeName = globalAppModel.prefs.themeName;
    _puzzleAppModel.prefs.pieceTheme = globalAppModel.prefs.pieceTheme;
    _puzzleAppModel.prefs.soundEnabled = globalAppModel.prefs.soundEnabled;
    _puzzleAppModel.prefs.hapticEnabled = globalAppModel.prefs.hapticEnabled;
    _puzzleAppModel.isTacticsMode = true;
    // CRITICAL: Disable the AI engine in the ephemeral puzzle AppModel.
    // With playerCount = 1 (the default), playingWithAI = true, which causes
    // GameController._moveCompletion() to trigger _aiMove() after every player
    // move — producing an unwanted second opponent move on top of the puzzle
    // controller's own _playOpponentMove(). Setting playerCount = 2 prevents this.
    _puzzleAppModel.playerCount = 2;

    _puzzleGameController = GameController(_puzzleAppModel);
    // Bind Flame game
    _chessGame = ChessGame(_puzzleGameController, _puzzleAppModel);

    _controller = TacticsPuzzleController(
      globalAppModel, // Uses global model for haptics/sounds
      mode: widget.mode,
      provider: widget.provider,
      judge: widget.judge,
    );

    _controller.gameController = _puzzleGameController;
    _puzzleGameController.onUserMoveCompleted = (move) {
      return _controller.handleUserMove(move);
    };
  }

  @override
  void dispose() {
    _puzzleGameController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TacticsPuzzleController>.value(
      value: _controller,
      child: Consumer2<AppModel, TacticsPuzzleController>(
        builder: (context, appModel, controller, child) {
          final theme = appModel.theme;

          return Scaffold(
            body: Container(
              decoration: BoxDecoration(gradient: theme.background),
              child: SafeArea(
                child: Column(
                  children: [
                    // ── HEADER ROW ───────────────────────────────────────────
                    _buildHeader(context, theme, controller),

                    if (controller.mode == TacticsMode.antiTactics ||
                        controller.mode == TacticsMode.antiTacticsV2)
                      _buildAntiTacticsStatsBar(theme, controller),

                    // ── PUZZLE INFO & RATING ─────────────────────────────────
                    _buildPuzzleInfo(theme, controller),

                    // ── CHESS BOARD ──────────────────────────────────────────
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: _buildBoard(appModel, controller),
                        ),
                      ),
                    ),

                    // ── STATUS TEXT ──────────────────────────────────────────
                    _buildStatusText(controller),

                    // ── COMPLETED PUZZLES SESSION LIST ───────────────────────
                    _buildCompletedPuzzlesRow(theme, controller),

                    // ── BOTTOM ACTIONS NAVIGATION & CONTROL BAR ──────────────
                    _buildBottomBar(theme, controller),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  void _showEndSessionDialog(BuildContext context, AppTheme theme,
      TacticsPuzzleController controller) {
    final solved = controller.sessionSolved;
    final attempted = controller.sessionAttempted;
    final accuracy = attempted == 0 ? 0.0 : (solved / attempted) * 100;
    final durationStr = _formatDuration(controller.sessionElapsedSeconds);

    showCupertinoDialog(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('Session beenden?'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'Möchtest du dein Taktik-Training für heute beenden?'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGroupedBackground
                        .resolveFrom(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _buildDialogStatRow('Gelöst', '$solved / $attempted'),
                      const SizedBox(height: 8),
                      _buildDialogStatRow(
                          'Genauigkeit', '${accuracy.toStringAsFixed(1)}%'),
                      const SizedBox(height: 8),
                      _buildDialogStatRow('Dauer', durationStr),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('Weiter trainieren'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss dialog
                Navigator.of(context).pop(); // Exit tactics view
              },
              child: const Text('Session beenden'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDialogStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
              fontSize: 14, color: CupertinoColors.secondaryLabel),
        ),
        Text(
          value,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: CupertinoColors.label),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, AppTheme theme,
      TacticsPuzzleController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => _showEndSessionDialog(context, theme, controller),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: theme.lightTile,
              size: 22,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                (widget.mode == TacticsMode.antiTactics ||
                        widget.mode == TacticsMode.antiTacticsV2)
                    ? (widget.mode == TacticsMode.antiTacticsV2
                        ? 'Anti-Tactics V2'
                        : 'Anti-Tactics')
                    : 'Classic Tactics',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.lightTile,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Session: ${_formatDuration(controller.sessionElapsedSeconds)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: theme.lightTile.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (controller.status == PuzzleStatus.loading)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: CupertinoActivityIndicator(
                    color: theme.lightTile,
                  ),
                ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () =>
                    _showEndSessionDialog(context, theme, controller),
                child: Text(
                  'End',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAntiTacticsStatsBar(
      AppTheme theme, TacticsPuzzleController controller) {
    final stats = controller.antiTacticsStats;
    if (stats == null) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.lightTile.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
                'Solved', '${stats.solved}/${stats.attempted}', theme),
            _buildStatItem(
                'Acc.', '${(stats.accuracy * 100).toStringAsFixed(1)}%', theme),
            _buildStatItem('Streak', '${stats.currentStreak}', theme),
            _buildStatItem('Best', '${stats.bestStreak}', theme),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, AppTheme theme) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: theme.lightTile.withValues(alpha: 0.5),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: theme.lightTile,
          ),
        ),
      ],
    );
  }

  Widget _buildPuzzleInfo(AppTheme theme, TacticsPuzzleController controller) {
    final rating = controller.rating;
    final task = controller.task;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'YOUR RATING',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: theme.lightTile.withValues(alpha: 0.5),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$rating ELO',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFE5E2E1),
                ),
              ),
            ],
          ),
          FutureBuilder<bool>(
            future: TacticsStorage.loadShowTimer(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data == true) {
                final seconds = controller.elapsedSeconds;
                final mins = (seconds ~/ 60).toString().padLeft(2, '0');
                final secs = (seconds % 60).toString().padLeft(2, '0');
                return Column(
                  children: [
                    Text(
                      'TIME',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: theme.lightTile.withValues(alpha: 0.5),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$mins:$secs',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: theme.lightTile,
                      ),
                    ),
                  ],
                );
              }
              return const SizedBox();
            },
          ),
          if (task != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'PUZZLE RATING',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: theme.lightTile.withValues(alpha: 0.5),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${task.effectiveDisplayRating} ELO',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: theme.lightTile,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBoard(AppModel appModel, TacticsPuzzleController controller) {
    if (controller.status == PuzzleStatus.loading) {
      return const CupertinoActivityIndicator(radius: 20);
    }
    if (controller.status == PuzzleStatus.error) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 48),
          const SizedBox(height: 12),
          Text(
            'Failed to load puzzle',
            style: TextStyle(color: appModel.theme.lightTile, fontSize: 16),
          ),
          const SizedBox(height: 16),
          CupertinoButton(
            color: appModel.theme.lightTile.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            onPressed: () => controller.fetchNextPuzzle(),
            child: Text(
              'Retry',
              style: TextStyle(color: appModel.theme.lightTile),
            ),
          )
        ],
      );
    }

    if (_chessGame != null) {
      // Rotate the board so Black is at the bottom for Black-to-move puzzles.
      // We set playerSide on the ephemeral AppModel so isBoardInverted returns
      // true, which ChessGame uses for its own internal rotation logic.
      _puzzleAppModel.playerSide = controller.playerColor == ch.Color.BLACK
          ? Player.player2
          : Player.player1;
    }

    final isBlack = controller.playerColor == ch.Color.BLACK;

    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4.0),
        child: Container(
          color: appModel.theme.darkTile,
          child: _chessGame == null
              ? const SizedBox()
              : RotatedBox(
                  quarterTurns: isBlack ? 2 : 0,
                  child: GameWidget(game: _chessGame!),
                ),
        ),
      ),
    );
  }

  Widget _buildStatusText(TacticsPuzzleController controller) {
    String text = 'Find the best move...';
    Color color = Colors.white70;
    String? explanation;

    switch (controller.status) {
      case PuzzleStatus.correct:
        text = 'Correct move! Keep going...';
        color = const Color(0xFF4CAF50);
        break;
      case PuzzleStatus.wrong:
        if ((controller.mode == TacticsMode.antiTactics ||
                controller.mode == TacticsMode.antiTacticsV2) &&
            controller.errorMessage.isNotEmpty) {
          text = controller.errorMessage;
        } else {
          text = 'Falscher Zug';
        }
        color = Colors.redAccent;
        break;
      case PuzzleStatus.solved:
        text = 'Richtig!';
        color = const Color(0xFF4CAF50);
        if ((controller.mode == TacticsMode.antiTactics ||
                controller.mode == TacticsMode.antiTacticsV2) &&
            controller.task?.explanation != null) {
          explanation = controller.task!.explanation;
        }
        break;
      case PuzzleStatus.resigned:
        text = 'Aufgegeben';
        color = Colors.orangeAccent;
        if ((controller.mode == TacticsMode.antiTactics ||
                controller.mode == TacticsMode.antiTacticsV2) &&
            controller.task?.explanation != null) {
          explanation = controller.task!.explanation;
        }
        break;
      case PuzzleStatus.hintActive:
        text = 'Hint: Move highlighted piece';
        color = Colors.lightBlueAccent;
        break;
      default:
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          if (explanation != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0, left: 24.0, right: 24.0),
              child: Text(
                explanation,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompletedPuzzlesRow(
      AppTheme theme, TacticsPuzzleController controller) {
    final history = controller.history;

    if (history.isEmpty) {
      return const SizedBox(height: 60);
    }

    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        itemCount: history.length,
        itemBuilder: (context, index) {
          final record = history[index];
          final isPositive = record.ratingChange >= 0;
          final color = isPositive
              ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
              : const Color(0xFFFF5252).withValues(alpha: 0.15);
          final textColor =
              isPositive ? const Color(0xFF4CAF50) : const Color(0xFFFF5252);
          final border = Border.all(
            color: isPositive
                ? const Color(0xFF4CAF50).withValues(alpha: 0.3)
                : const Color(0xFFFF5252).withValues(alpha: 0.3),
            width: 1,
          );

          return GestureDetector(
            onTap: () {
              // Optionally add a tiny haptic feedback here
              controller.reviewPuzzle(record.puzzleId);
            },
            child: Container(
              width: 50,
              height: 50,
              margin:
                  const EdgeInsets.symmetric(horizontal: 4.0, vertical: 5.0),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
                border: border,
              ),
              child: Center(
                child: Text(
                  '${isPositive ? '+' : ''}${record.ratingChange}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomBar(AppTheme theme, TacticsPuzzleController controller) {
    final activeColor = theme.lightTile;
    final inactiveColor = theme.lightTile.withValues(alpha: 0.25);

    // If puzzle solved or resigned, show Engine, Navigation, and Next Puzzle
    if (controller.status == PuzzleStatus.solved ||
        controller.status == PuzzleStatus.resigned) {
      return Container(
        height: 64,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: [
            // Engine Button (Internal Game Analysis)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              onPressed: () {
                if (controller.task == null) return;

                final movesStr = controller.playedUciMoves.join(' ');
                final gameEntry = GameEntry(
                  platform: GamePlatform.local,
                  white: 'White',
                  black: 'Black',
                  winner: 'draw',
                  speed: 'local',
                  pgn: '',
                  moves: movesStr,
                );

                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (_) => GameAnalysisPage(
                      fen: controller.task!.fen,
                      game: gameEntry,
                    ),
                  ),
                );
              },
              child: Icon(Icons.manage_search_rounded,
                  color: activeColor, size: 30),
            ),
            const SizedBox(width: 8),
            // Chevrons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  onPressed:
                      controller.canGoBack ? () => controller.goBack() : null,
                  child: Icon(
                    Icons.chevron_left_rounded,
                    color: controller.canGoBack ? activeColor : inactiveColor,
                    size: 32,
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  onPressed: controller.canGoForward
                      ? () => controller.goForward()
                      : null,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color:
                        controller.canGoForward ? activeColor : inactiveColor,
                    size: 32,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: CupertinoButton(
                color: theme.lightTile.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                padding: EdgeInsets.zero,
                onPressed: () => controller.fetchNextPuzzle(),
                child: Text(
                  'Next Puzzle',
                  style: TextStyle(
                    color: theme.lightTile,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ── Resign ──
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => controller.resign(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.flag_rounded, color: Colors.orangeAccent, size: 22),
                const SizedBox(height: 4),
                Text(
                  'Resign',
                  style: TextStyle(fontSize: 10, color: theme.lightTile),
                ),
              ],
            ),
          ),

          // ── No Tactic Button (Anti-Tactics Only) ──
          if (controller.task?.mode == TacticsMode.antiTactics ||
              controller.task?.mode == TacticsMode.antiTacticsV2)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.redAccent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              onPressed: () =>
                  controller.handleAction(TacticsAction.declareNoTactic),
              child: Text(
                'No Tactic',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.redAccent,
                ),
              ),
            ),

          // ── Chevrons for history browsing ──
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                onPressed:
                    controller.canGoBack ? () => controller.goBack() : null,
                child: Icon(
                  Icons.chevron_left_rounded,
                  color: controller.canGoBack ? activeColor : inactiveColor,
                  size: 32,
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                onPressed: controller.canGoForward
                    ? () => controller.goForward()
                    : null,
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: controller.canGoForward ? activeColor : inactiveColor,
                  size: 32,
                ),
              ),
            ],
          ),

          // ── Hint ──
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => controller.requestHint(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lightbulb_outline_rounded,
                    color: Colors.yellowAccent, size: 22),
                const SizedBox(height: 4),
                Text(
                  'Hint',
                  style: TextStyle(fontSize: 10, color: theme.lightTile),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
