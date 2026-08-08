import 'package:flame/game.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as rp;
import 'package:provider/provider.dart' as prov;

import '../../../logic/chess_game.dart';
import '../../../logic/chess_piece.dart';
import '../../../logic/game_controller.dart';
import '../../../logic/move_calculation/move_classes/move.dart';
import '../../../logic/move_calculation/move_classes/move_meta.dart';
import '../../../logic/peeking_notifier.dart';
import '../../../logic/shared_functions.dart';
import '../../../model/app_model.dart';
import '../../../model/app_themes.dart';
import '../../../model/player.dart';
import 'game_info_and_controls/timer_widget.dart';
import 'game_over_overlay.dart';

/// Snapshot Chess mode screen.
///
/// The live Flame board is always visible at the top. The input grid (same
/// piece→file→rank flow as Blind mode) sits compactly at the bottom. A single
/// "Update" button snaps the board's frozen visual display to the current live
/// engine position when tapped.
class SnapshotChessScreen extends StatefulWidget {
  final GameController controller;
  final ChessGame chessGame;

  const SnapshotChessScreen({
    Key? key,
    required this.controller,
    required this.chessGame,
  }) : super(key: key);

  @override
  State<SnapshotChessScreen> createState() => _SnapshotChessScreenState();
}

class _SnapshotChessScreenState extends State<SnapshotChessScreen>
    with TickerProviderStateMixin {
  int _step = 0; // 0: Piece, 1: File, 2: Rank, 3: Disambiguate
  ChessPieceType? _pieceType;
  String? _destFile;
  String? _destRank;
  List<ChessPiece> _candidates = [];

  String? _errorMessage;
  bool _showError = false;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  // Opponent move animation state
  late AnimationController _opponentMoveCtrl;
  String _animatedOpponentMoveStr = '';
  bool _showOpponentMoveAnim = false;
  int _lastMoveCount = 0;
  AppModel? _appModel;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnim = Tween<double>(begin: 0, end: 10)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeCtrl);

    _opponentMoveCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500));
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    _opponentMoveCtrl.dispose();
    _appModel?.removeListener(_onModelChanged);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final model = prov.Provider.of<AppModel>(context, listen: false);
    if (_appModel != model) {
      _appModel?.removeListener(_onModelChanged);
      _appModel = model;
      _appModel?.addListener(_onModelChanged);
      _lastMoveCount = _appModel?.moveMetaList.length ?? 0;
    }
  }

  void _onModelChanged() {
    if (!mounted) return;
    final currentCount = _appModel?.moveMetaList.length ?? 0;
    if (currentCount > _lastMoveCount) {
      final lastMeta = _appModel!.moveMetaList.last;
      final isOpponentMove = _appModel!.playingWithAI
          ? (lastMeta.player != _appModel!.playerSide &&
              _appModel!.turn == _appModel!.playerSide)
          : true;
      if (isOpponentMove) {
        _triggerOpponentMoveAnimation(lastMeta);
      }
      _lastMoveCount = currentCount;
    } else if (currentCount < _lastMoveCount) {
      _lastMoveCount = currentCount;
    }
  }

  void _triggerOpponentMoveAnimation(MoveMeta meta) {
    setState(() {
      _animatedOpponentMoveStr = _moveToLongString(meta);
      _showOpponentMoveAnim = true;
    });
    _opponentMoveCtrl.forward(from: 0).then((_) {
      if (mounted) {
        setState(() {
          _showOpponentMoveAnim = false;
        });
      }
    });
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  String _moveToLongString(MoveMeta meta) => meta.toLongString();

  // ── State machine helpers ────────────────────────────────────────────────

  String _pieceSpokenName(ChessPieceType type) {
    switch (type) {
      case ChessPieceType.king:
        return 'King';
      case ChessPieceType.queen:
        return 'Queen';
      case ChessPieceType.rook:
        return 'Rook';
      case ChessPieceType.bishop:
        return 'Bishop';
      case ChessPieceType.knight:
        return 'Knight';
      case ChessPieceType.pawn:
        return 'Pawn';
      default:
        return '';
    }
  }

  void _reset({String? error}) {
    setState(() {
      _step = 0;
      _pieceType = null;
      _destFile = null;
      _destRank = null;
      _candidates = [];
      if (error != null) {
        _errorMessage = error;
        _showError = true;
      }
    });
    if (error != null) {
      prov.Provider.of<AppModel>(context, listen: false).speak(error);
      _shakeCtrl.forward(from: 0);
      Future.delayed(
        const Duration(milliseconds: 2000),
        () => mounted ? setState(() => _showError = false) : null,
      );
    }
  }

  void _stepBack() {
    setState(() {
      if (_step > 0) _step--;
      if (_step == 0) _pieceType = null;
      if (_step == 1) _destFile = null;
      if (_step == 2) _destRank = null;
      if (_step == 3) _candidates = [];
    });
  }

  void _handlePieceSelected(ChessPieceType type) {
    setState(() {
      _pieceType = type;
      _step = 1;
    });
    prov.Provider.of<AppModel>(context, listen: false)
        .speak(_pieceSpokenName(type));
  }

  void _handleFile(String file) {
    setState(() {
      _destFile = file;
      _step = 2;
    });
    prov.Provider.of<AppModel>(context, listen: false)
        .speak(file.toUpperCase());
  }

  void _handleRank(String rank) {
    setState(() {
      _destRank = rank;
    });
    prov.Provider.of<AppModel>(context, listen: false).speak(rank);
    _evaluateMove();
  }

  void _evaluateMove() {
    if (_pieceType == null || _destFile == null || _destRank == null) return;
    final sq = '$_destFile$_destRank';

    int? destTile;
    final file = sq[0].toLowerCase().codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rankVal = int.tryParse(sq[1]);
    if (file >= 0 &&
        file <= 7 &&
        rankVal != null &&
        rankVal >= 1 &&
        rankVal <= 8) {
      final row = 8 - rankVal;
      destTile = row * 8 + file;
    }

    if (destTile == null) {
      _reset(error: 'Invalid Square');
      return;
    }

    final board = widget.controller.board;
    final turn = prov.Provider.of<AppModel>(context, listen: false).turn;
    final friendlyPieces =
        turn == Player.player1 ? board.player1Pieces : board.player2Pieces;

    final List<ChessPiece> validCandidates = [];
    for (var p in friendlyPieces) {
      if (p.type == _pieceType) {
        final legalMoves = board.movesForPiece(p);
        if (legalMoves.contains(destTile)) {
          validCandidates.add(p);
        }
      }
    }

    if (validCandidates.isEmpty) {
      _reset(error: 'Illegal Move');
    } else if (validCandidates.length == 1) {
      _executeMove(validCandidates.first, destTile);
    } else {
      setState(() {
        _candidates = validCandidates;
        _step = 3;
      });
    }
  }

  void _executeMove(ChessPiece piece, int toTile) {
    final ok = widget.controller.submitDirectMove(Move(piece.tile, toTile));
    if (ok) {
      _reset();
    } else {
      _reset(error: 'Illegal Move');
    }
  }

  String _tileToSquare(int tile) {
    final col = tile % 8;
    final row = (tile / 8).floor();
    final f = String.fromCharCode('a'.codeUnitAt(0) + col);
    final r = (8 - row).toString();
    return '$f$r';
  }

  String get _partialDisplay {
    if (_showError) return _errorMessage ?? '';

    String pieceName = '';
    switch (_pieceType) {
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

    if (_step == 0) return '';
    if (_step == 1) return '$pieceName _';
    if (_step == 2) return '$pieceName $_destFile _';
    if (_step == 3) return '$pieceName $_destFile$_destRank (?)';
    return '';
  }

  String _stepLabel() {
    switch (_step) {
      case 0:
        return 'Piece';
      case 1:
        switch (_pieceType) {
          case ChessPieceType.king:
            return 'King';
          case ChessPieceType.queen:
            return 'Queen';
          case ChessPieceType.rook:
            return 'Rook';
          case ChessPieceType.bishop:
            return 'Bishop';
          case ChessPieceType.knight:
            return 'Knight';
          case ChessPieceType.pawn:
            return 'Pawn';
          default:
            return '';
        }
      case 2:
        return _destFile?.toUpperCase() ?? '';
      case 3:
        return 'Piece';
      default:
        return '';
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final appModel = prov.Provider.of<AppModel>(context);
    final theme = appModel.theme;

    return rp.Consumer(
      builder: (context, ref, _) {
        final peekState = ref.watch(peekingProvider);
        final isWhiteTurn = appModel.turn == Player.player1;
        final tokens =
            isWhiteTurn ? peekState.player1Tokens : peekState.player2Tokens;
        final moves =
            isWhiteTurn ? peekState.player1Moves : peekState.player2Moves;
        final frequency = peekState.peekFrequency;

        final moveCount = appModel.moveMetaList.length;
        final moveNumber = (moveCount ~/ 2) + 1;
        final hasTimer = appModel.timeLimit > 0;

        final isAIsTurn =
            appModel.playingWithAI && appModel.turn != appModel.playerSide;

        final bgGrad = theme.background ??
            const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0A0F0C), Color(0xFF111A14)],
            );

        final playerColorSuffix = isWhiteTurn ? 'white' : 'black';
        final formattedTheme = formatPieceTheme(appModel.prefs.pieceTheme);

        return Stack(
          children: [
            Container(
              decoration: BoxDecoration(gradient: bgGrad),
              child: SafeArea(
                child: Column(
                  children: [
                    // ── Top Bar with Exit/Back Button ──────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: CupertinoButton(
                          padding: const EdgeInsets.all(8),
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: Icon(
                            Icons.arrow_back_ios_new,
                            size: 20,
                            color: theme.lightTile,
                          ),
                        ),
                      ),
                    ),

                    // ── Timers ────────────────────────────────────────────────────
                    if (hasTimer)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TimerWidget(
                                timeLeft: appModel.player1TimeLeft,
                                delayLeft:
                                    appModel.timerService.player1DelayLeft,
                                isActive: appModel.turn == Player.player1,
                                label: appModel.playingWithAI
                                    ? (appModel.playerSide == Player.player1
                                        ? 'YOU'
                                        : (appModel.aiEngine == 'maya'
                                            ? 'MAYA'
                                            : 'STOCKFISH'))
                                    : 'WHITE',
                                theme: theme,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TimerWidget(
                                timeLeft: appModel.player2TimeLeft,
                                delayLeft:
                                    appModel.timerService.player2DelayLeft,
                                isActive: appModel.turn == Player.player2,
                                label: appModel.playingWithAI
                                    ? (appModel.playerSide == Player.player2
                                        ? 'YOU'
                                        : (appModel.aiEngine == 'maya'
                                            ? 'MAYA'
                                            : 'STOCKFISH'))
                                    : 'BLACK',
                                theme: theme,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const SizedBox(height: 8),

                    // ── Move counter / turn info ───────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Mode badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: theme.moveHint.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: theme.moveHint.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.camera_alt_outlined,
                                    size: 14, color: theme.lightTile),
                                const SizedBox(width: 5),
                                Text(
                                  'SNAPSHOT',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5,
                                    color: theme.lightTile,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Move $moveNumber',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFFE5E2E1),
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isWhiteTurn
                                    ? '⬜ White to move'
                                    : '⬛ Black to move',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: theme.lightTile.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ── Board Area ────────────────────────────────────────────────
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: IgnorePointer(
                              ignoring: true,
                              child: RotatedBox(
                                quarterTurns: appModel.isBoardInverted ? 2 : 0,
                                child: GameWidget(
                                  game: widget.chessGame,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ── Move Input Readout ─────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          // Step label (tiny, on left)
                          SizedBox(
                            width: 48,
                            child: Text(
                              _stepLabel(),
                              style: TextStyle(
                                color: theme.lightTile.withValues(alpha: 0.5),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Partial move display
                          Expanded(
                            child: AnimatedBuilder(
                              animation: _shakeAnim,
                              builder: (_, child) => Transform.translate(
                                offset: Offset(
                                  _showError
                                      ? _shakeAnim.value *
                                          ((_shakeCtrl.value < 0.5) ? 1 : -1)
                                      : 0,
                                  0,
                                ),
                                child: child,
                              ),
                              child: Text(
                                _partialDisplay.isEmpty && !_showError
                                    ? (isAIsTurn ? 'Engine Thinking...' : '')
                                    : _partialDisplay,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'monospace',
                                  letterSpacing: 2,
                                  color: _showError
                                      ? const Color(0xFFFF5252)
                                      : isAIsTurn
                                          ? theme.lightTile
                                              .withValues(alpha: 0.6)
                                          : const Color(0xFFE5E2E1),
                                ),
                              ),
                            ),
                          ),
                          // Back step button
                          if (_step > 0 && !isAIsTurn)
                            CupertinoButton(
                              padding: const EdgeInsets.all(6),
                              onPressed: _stepBack,
                              child: Icon(Icons.backspace_outlined,
                                  size: 16,
                                  color:
                                      theme.lightTile.withValues(alpha: 0.7)),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ── Input Grid or Animation ─────────────────────────────────────
                    if (_showOpponentMoveAnim)
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 24.0),
                          child: Stack(
                            children: [
                              AnimatedBuilder(
                                animation: _opponentMoveCtrl,
                                builder: (context, child) {
                                  final animProgress = _opponentMoveCtrl.value;
                                  double slideProgress = 0.0;
                                  if (animProgress > 0.8) {
                                    slideProgress = Curves.easeInOut
                                        .transform((animProgress - 0.8) / 0.2);
                                  }

                                  final alignment = Alignment.lerp(
                                      Alignment.center,
                                      Alignment.bottomCenter,
                                      slideProgress)!;
                                  final double scale =
                                      _lerp(2.2, 1.0, slideProgress);
                                  final double opacity =
                                      _lerp(1.0, 0.7, slideProgress);

                                  return Align(
                                    alignment: alignment,
                                    child: Transform.scale(
                                      scale: scale,
                                      child: Opacity(
                                        opacity: opacity,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.history_rounded,
                                              size: 14,
                                              color: theme.lightTile
                                                  .withValues(alpha: 0.6),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              slideProgress > 0.2
                                                  ? "Opponent's Last Move: $_animatedOpponentMoveStr"
                                                  : _animatedOpponentMoveStr,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: theme.lightTile,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      Expanded(
                        flex: 2,
                        child: isAIsTurn
                            ? Center(
                                child: Text(
                                  'Engine Thinking...',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        theme.lightTile.withValues(alpha: 0.5),
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              )
                            : Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: _buildInputGrid(
                                    theme, formattedTheme, playerColorSuffix),
                              ),
                      ),

                      // ── Opponent's Last Move display ─────────────────────────────
                      if (appModel.moveMetaList.isNotEmpty)
                        () {
                          final lastMeta = appModel.moveMetaList.last;
                          final isOpponentMove =
                              lastMeta.player != appModel.turn;
                          if (isOpponentMove) {
                            final moveStr = _moveToLongString(lastMeta);
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.history_rounded,
                                      size: 14,
                                      color: theme.lightTile
                                          .withValues(alpha: 0.5)),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Opponent's Last Move: $moveStr",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: theme.lightTile
                                          .withValues(alpha: 0.7),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        }()
                      else
                        const SizedBox.shrink(),
                    ],

                    // ── Action bar ────────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Resign
                          _SmallActionBtn(
                            icon: Icons.flag_outlined,
                            label: 'Resign',
                            theme: theme,
                            colorOverride: Colors.redAccent,
                            onTap: () {
                              appModel.haptic.medium();
                              appModel.endGame(
                                  winner: oppositePlayer(appModel.turn));
                            },
                          ),
                          // Update board with token logic & progress background
                          _UpdateButton(
                            theme: theme,
                            tokens: tokens,
                            moves: moves,
                            frequency: frequency,
                            onTap: () {
                              appModel.haptic.light();
                              final ok = ref
                                  .read(peekingProvider.notifier)
                                  .consumeTokenForUpdate(appModel.turn);
                              if (ok) {
                                widget.controller.updateBoard();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (appModel.gameOver)
              GameOverOverlay(
                appModel: appModel,
                onReviewGame: () {},
              ),
          ],
        );
      },
    );
  }

  Widget _buildInputGrid(
      AppTheme theme, String formattedTheme, String playerColorSuffix) {
    if (_step == 0) {
      final pieces = [
        ChessPieceType.king,
        ChessPieceType.queen,
        ChessPieceType.rook,
        ChessPieceType.bishop,
        ChessPieceType.knight,
        ChessPieceType.pawn,
      ];
      return GridView.count(
        crossAxisCount: 6,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        physics: const NeverScrollableScrollPhysics(),
        children: pieces.map((p) {
          final pStr = pieceTypeToString(p);
          return _SnapGridButton(
            theme: theme,
            onTap: () => _handlePieceSelected(p),
            child: Image.asset(
              'assets/images/pieces/$formattedTheme/${pStr}_$playerColorSuffix.png',
              width: 28,
              height: 28,
            ),
          );
        }).toList(),
      );
    } else if (_step == 1) {
      return _buildLettersGrid(
          theme, const ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'], _handleFile);
    } else if (_step == 2) {
      return _buildLettersGrid(
          theme, const ['1', '2', '3', '4', '5', '6', '7', '8'], _handleRank);
    } else if (_step == 3) {
      return GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        physics: const NeverScrollableScrollPhysics(),
        children: _candidates.map((c) {
          final sq = _tileToSquare(c.tile);
          return _SnapGridButton(
            theme: theme,
            onTap: () {
              final sqDest = '$_destFile$_destRank';
              int? destTile;
              final file =
                  sqDest[0].toLowerCase().codeUnitAt(0) - 'a'.codeUnitAt(0);
              final rankVal = int.tryParse(sqDest[1]);
              if (file >= 0 &&
                  file <= 7 &&
                  rankVal != null &&
                  rankVal >= 1 &&
                  rankVal <= 8) {
                final row = 8 - rankVal;
                destTile = row * 8 + file;
              }
              if (destTile != null) {
                _executeMove(c, destTile);
              }
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/pieces/$formattedTheme/${pieceTypeToString(c.type)}_$playerColorSuffix.png',
                  width: 24,
                  height: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  sq,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.lightTile,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildLettersGrid(
      AppTheme theme, List<String> items, Function(String) onSelect) {
    return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      physics: const NeverScrollableScrollPhysics(),
      children: items.map((label) {
        return _SnapGridButton(
          theme: theme,
          onTap: () => onSelect(label),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: theme.lightTile,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SnapGridButton extends StatelessWidget {
  final AppTheme theme;
  final Widget child;
  final VoidCallback onTap;

  const _SnapGridButton(
      {required this.theme, required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: theme.darkTile.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.lightTile.withValues(alpha: 0.18),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

class _SmallActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final AppTheme theme;
  final VoidCallback onTap;
  final Color? colorOverride;

  const _SmallActionBtn({
    required this.icon,
    required this.label,
    required this.theme,
    required this.onTap,
    this.colorOverride,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorOverride ?? theme.lightTile;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorOverride != null
              ? colorOverride!.withValues(alpha: 0.1)
              : theme.moveHint.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateButton extends StatelessWidget {
  final AppTheme theme;
  final int tokens;
  final int moves;
  final int frequency;
  final VoidCallback onTap;

  const _UpdateButton({
    required this.theme,
    required this.tokens,
    required this.moves,
    required this.frequency,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double progress =
        tokens > 0 ? 1.0 : (moves / frequency).clamp(0.0, 1.0);
    final bool isEnabled = tokens > 0;
    final color =
        isEnabled ? theme.lightTile : theme.lightTile.withValues(alpha: 0.3);

    String text;
    if (isEnabled) {
      text = 'Update ($tokens)';
    } else {
      text = 'Update ($moves/$frequency)';
    }

    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 150, // standard width matching Resign
          height: 38,
          decoration: BoxDecoration(
            color: theme.moveHint.withValues(alpha: 0.08),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              // Progress Bar fill
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: Container(
                    color: isEnabled
                        ? theme.moveHint.withValues(alpha: 0.25)
                        : theme.moveHint.withValues(alpha: 0.1),
                  ),
                ),
              ),
              // Content
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sync_rounded, size: 14, color: color),
                    const SizedBox(width: 5),
                    Text(
                      text,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
