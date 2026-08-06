import 'dart:ui';

import 'package:confetti/confetti.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer, Provider;
import 'package:flutter_riverpod/flutter_riverpod.dart' as rp;
import 'package:provider/provider.dart';

import '../logic/chess_game.dart';
import '../logic/game_controller.dart';
import '../logic/game_mode_notifier.dart';
import '../logic/peeking_notifier.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';

import 'components/chess_view/blind_chess_screen.dart';
import 'components/chess_view/chess_board_widget.dart';
import 'components/chess_view/game_info_and_controls.dart';
import 'components/chess_view/game_info_and_controls/game_status.dart';
import 'components/chess_view/game_over_overlay.dart';
import 'components/chess_view/promotion_dialog.dart';
import 'components/chess_view/snapshot_chess_screen.dart';
import 'components/shared/bottom_padding.dart';
import 'components/shared/glass_panel.dart';
import 'settings_view.dart';

class ChessView extends StatefulWidget {
  final AppModel appModel;
  final bool isResuming;
  final ChessMode mode;

  ChessView(this.appModel,
      {this.isResuming = false, this.mode = ChessMode.normal});

  @override
  _ChessViewState createState() => _ChessViewState(appModel);
}

class _ChessViewState extends State<ChessView> with WidgetsBindingObserver {
  AppModel appModel;
  ChessGame? chessGame;
  late ConfettiController _confettiController;
  bool _hideGameOverOverlay = false;

  _ChessViewState(this.appModel);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 5));

    // Defer game initialization to after the page transition completes.
    // This prevents heavy work (sprite creation, board setup) from
    // blocking the navigation animation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isResuming) {
        appModel.restoreGameState().then((_) {
          _initFlameGame();
          if (appModel.gameMode == ChessMode.blind ||
              appModel.gameMode == ChessMode.snapshot) {
            appModel.gameController?.isResumingPeek = true;
            providerContainer
                .read(peekingProvider.notifier)
                .triggerResumePeek();
            if (appModel.gameMode == ChessMode.snapshot) {
              appModel.gameController?.startSnapshotPeek();
            }
          }
        });
      } else {
        appModel.newGame(notify: false, mode: widget.mode);
        _initFlameGame();
      }
    });
  }

  void _initFlameGame() {
    if (appModel.gameController != null) {
      setState(() {
        chessGame = ChessGame(appModel.gameController!, appModel);
      });
      // Defer notifying listeners if needed to let the flame engine setup
      Future.delayed(Duration(milliseconds: 50), () {
        if (mounted) appModel.update();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _confettiController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (!appModel.gameOver) {
        appModel.saveGameStateImmediate();
        appModel.timerService.pause();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (!appModel.gameOver) {
        appModel.timerService.resume();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppModel>(
      builder: (context, appModel, child) {
        final theme = appModel.theme;
        // Show themed background while game initializes
        if (appModel.gameController == null || chessGame == null) {
          return Container(
            decoration: BoxDecoration(gradient: theme.background),
          );
        }

        if (chessGame != null &&
            appModel.gameController != null &&
            chessGame!.controller != appModel.gameController) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _initFlameGame();
          });
          return Container(
            decoration: BoxDecoration(gradient: theme.background),
          );
        }

        if (appModel.promotionRequested) {
          appModel.promotionRequested = false;
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _showPromotionDialog(appModel));
        }

        if (appModel.gameOver && appModel.userWon) {
          _confettiController.play();
        } else {
          _confettiController.stop();
        }

        return rp.Consumer(
          builder: (context, ref, _) {
            final peekState = ref.watch(peekingProvider);
            final isPeeking = appModel.gameMode == ChessMode.blind &&
                peekState.showBoardOverride;

            if (appModel.gameMode == ChessMode.blind && !isPeeking) {
              return PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, result) async {
                  if (didPop) return;
                  if (appModel.gameOver) {
                    appModel.exitChessView();
                    Navigator.of(context).pop();
                  } else {
                    showExitDialog(context);
                  }
                },
                child: BlindChessScreen(
                  controller: appModel.gameController!,
                  chessGame: chessGame!,
                ),
              );
            }

            if (appModel.gameMode == ChessMode.snapshot) {
              return PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, result) async {
                  if (didPop) return;
                  if (appModel.gameOver) {
                    appModel.exitChessView();
                    Navigator.of(context).pop();
                  } else {
                    showExitDialog(context);
                  }
                },
                child: SnapshotChessScreen(
                  controller: appModel.gameController!,
                  chessGame: chessGame!,
                ),
              );
            }

            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) async {
                if (didPop) return;
                if (appModel.gameOver) {
                  appModel.exitChessView();
                  Navigator.of(context).pop();
                } else {
                  showExitDialog(context);
                }
              },
              child: Stack(
                children: [
                  // ── Static background ──────────────────────────────────────
                  // Driven by Selector so it only rebuilds on theme change,
                  // NOT on every move / AI turn / timer tick.
                  Positioned.fill(
                    child: Selector<AppModel, AppTheme>(
                      selector: (_, m) => m.theme,
                      builder: (_, theme, __) => _ChessBackground(theme: theme),
                    ),
                  ),

                  // ── Game content ───────────────────────────────────────────
                  SafeArea(
                    child: Column(
                      children: [
                        // Top App Bar
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: appModel.playerCount == 1
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '${appModel.aiEngine == 'maya' ? 'Maya' : 'Stockfish'} L${appModel.aiDifficulty}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: theme.lightTile
                                                    .withValues(alpha: 0.6),
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '(${AppModel.getDifficultyElo(appModel.aiDifficulty)} ELO)',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w500,
                                                color: theme.lightTile
                                                    .withValues(alpha: 0.45),
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                              GameStatus(),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        CupertinoPageRoute(
                                          builder: (context) =>
                                              const SettingsView(),
                                        ),
                                      );
                                    },
                                    child: Icon(
                                      Icons.settings_rounded,
                                      color: theme.lightTile,
                                      size: 24,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 0),
                            child: Center(
                              child: ChessBoardWidget(appModel, chessGame!),
                            ),
                          ),
                        ),

                        // Peek Countdown
                        if (isPeeking)
                          PeekCountdownOverlay(
                            hasGameTimer: appModel.timeLimit > 0,
                            isResume: appModel.gameController?.isResumingPeek ??
                                false,
                            onClose: () {
                              appModel.gameController?.isResumingPeek = false;
                              ref
                                  .read(peekingProvider.notifier)
                                  .resetPeekOverride();
                            },
                          ),

                        // Controls and Buttons at the bottom
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          child: GameInfoAndControls(appModel),
                        ),
                        BottomPadding(),
                      ],
                    ),
                  ),

                  Align(
                    alignment: Alignment.topCenter,
                    child: ConfettiWidget(
                      key: ValueKey('${theme.name}_confetti'),
                      confettiController: _confettiController,
                      blastDirectionality: BlastDirectionality.explosive,
                      shouldLoop: false,
                      colors: _getConfettiColors(theme),
                    ),
                  ),

                  // ── Cloud Server Warmup Overlay ──
                  if (appModel.playerCount == 1 &&
                      !appModel.isServerAwake &&
                      appModel.isServerWarmingUp)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap:
                            () {}, // swallow taps so they don't reach the board
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.4),
                          child: BackdropFilter(
                            filter:
                                ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                            child: Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 40),
                                child: GlassPanel(
                                  borderRadius: 24,
                                  color: theme.darkTile.withValues(alpha: 0.4),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const SizedBox(height: 12),
                                        const CupertinoActivityIndicator(
                                          radius: 18,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(height: 24),
                                        const Text(
                                          'Verbindung zum Cloud-Server wird aufgebaut...',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.5,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Bitte warten Sie noch ${appModel.serverWarmUpSecondsLeft} Sekunden.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.7),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w400,
                                            letterSpacing: 0.2,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                        const SizedBox(height: 28),
                                        CupertinoButton(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 28, vertical: 12),
                                          color: Colors.white
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                          },
                                          child: const Text(
                                            'Back',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // The Peek countdown overlay was moved into the column above
                  if (appModel.gameOver && !_hideGameOverOverlay)
                    GameOverOverlay(
                      appModel: appModel,
                      onReviewGame: () {
                        setState(() {
                          _hideGameOverOverlay = true;
                        });
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<Color> _getConfettiColors(AppTheme theme) {
    final List<Color> result = [];
    final candidates = [
      theme.lightTile,
      theme.moveHint,
      theme.latestMove,
      theme.notation,
    ];
    for (final color in candidates) {
      final hsv = HSVColor.fromColor(color);
      final saturation = hsv.saturation > 0.6 ? hsv.saturation : 0.6;
      final value = hsv.value > 0.8 ? hsv.value : 0.8;
      result.add(hsv.withSaturation(saturation).withValue(value).toColor());
    }
    return result;
  }

  void _showPromotionDialog(AppModel appModel) {
    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) {
        return PromotionDialog(appModel);
      },
    );
  }
}

/// Overlay shown on the normal board when a Blind-mode peek is active.
/// Displays a countdown (1 min if no game timer) and a "Back to Blind" button.
class PeekCountdownOverlay extends ConsumerStatefulWidget {
  final bool hasGameTimer;
  final bool isResume;
  final VoidCallback onClose;

  const PeekCountdownOverlay({
    required this.hasGameTimer,
    this.isResume = false,
    required this.onClose,
  });

  @override
  ConsumerState<PeekCountdownOverlay> createState() =>
      PeekCountdownOverlayState();
}

class PeekCountdownOverlayState extends ConsumerState<PeekCountdownOverlay> {
  int _secondsLeft = 60;
  bool _useCountdown = true;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.isResume ? 30 : 60;
    _startCountdown();
  }

  void _startCountdown() async {
    while (mounted && _secondsLeft > 0) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) setState(() => _secondsLeft--);
    }
    if (mounted && _secondsLeft == 0) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: SafeArea(
        child: GlassPanel(
          borderRadius: 20,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.visibility_rounded,
                      color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'PEEKING',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: Colors.white70,
                    ),
                  ),
                  if (_useCountdown) ...[
                    const SizedBox(width: 12),
                    Text(
                      '${_secondsLeft}s',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: widget.onClose,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2), width: 1),
                  ),
                  child: const Text(
                    'Back to Blind',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Static decorative background for [ChessView].
///
/// Separated from the game-content [Consumer] so it is only rebuilt when the
/// theme changes — not on every move, AI result, or timer tick.
class _ChessBackground extends StatelessWidget {
  final AppTheme theme;

  const _ChessBackground({required this.theme});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        children: [
          // Gradient fill
          Container(
            decoration: BoxDecoration(gradient: theme.background),
          ),

          // Dot grid
          Positioned.fill(
            child: CustomPaint(
              painter: DotGridPainter(
                color: theme.lightTile.withValues(alpha: 0.04),
              ),
            ),
          ),

          // Glow blobs — RepaintBoundary keeps the expensive boxShadow on its
          // own GPU layer so the Selector's infrequent rebuilds don't cause jank.
          Positioned(
            top: 150,
            right: -50,
            child: RepaintBoundary(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: theme.lightTile.withValues(alpha: 0.05),
                      blurRadius: 120,
                      spreadRadius: 30,
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 100,
            left: -50,
            child: RepaintBoundary(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: theme.darkTile.withValues(alpha: 0.04),
                      blurRadius: 100,
                      spreadRadius: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void showExitDialog(BuildContext context) {
  final appModel = Provider.of<AppModel>(context, listen: false);
  appModel.timerService.pause();
  showGeneralDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    barrierDismissible: true,
    barrierLabel: '',
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dialogContext, anim1, anim2) {
      return Selector<AppModel, AppTheme>(
        selector: (_, m) => m.theme,
        builder: (dialogContext, theme, child) => Center(
          child: Material(
            color: Colors.transparent,
            child: GlassPanel(
              borderRadius: 24,
              padding: const EdgeInsets.all(20),
              color: const Color(0x80201F1F),
              animation: anim1,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Leave Game',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE5E2E1),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Would you like to save your progress\nbefore exiting? You can resume\nfrom this exact position later',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFFC3C8C2),
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    // Actions Column
                    Column(
                      children: [
                        // Save & Exit (Solid Premium Button)
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            final appModel =
                                Provider.of<AppModel>(context, listen: false);
                            appModel.saveAndExitChessView();
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            width: double.infinity,
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: const Color(0xFFF5F5F0),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x20000000),
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ]),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.save_rounded,
                                    color: const Color(0xFF131313), size: 18),
                                const SizedBox(width: 8),
                                const Text(
                                  'Save & Exit',
                                  style: TextStyle(
                                    color: Color(0xFF131313),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Exit Without Saving (Glass / Outline Button)
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            final appModel =
                                Provider.of<AppModel>(context, listen: false);
                            appModel.exitChessView();
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            width: double.infinity,
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0x30F5F5F0),
                                width: 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.close_rounded,
                                    color: const Color(0xFFE5E2E1), size: 18),
                                const SizedBox(width: 8),
                                const Text(
                                  'Exit Without Saving',
                                  style: TextStyle(
                                    color: Color(0xFFE5E2E1),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Cancel (Clean Text Button)
                        CupertinoButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: Color(0xFF8D928C),
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, anim1, anim2, child) {
      return FadeTransition(
        opacity: anim1.drive(
          CurveTween(curve: Curves.easeOut),
        ),
        child: child,
      );
    },
  ).then((_) {
    if (!appModel.gameOver) {
      appModel.timerService.resume();
    }
  });
}
