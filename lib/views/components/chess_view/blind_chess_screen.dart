import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../shared/glass_panel.dart';
import 'game_info_and_controls/timer_widget.dart';

class BlindChessScreen extends ConsumerStatefulWidget {
  final GameController controller;
  final ChessGame chessGame;

  const BlindChessScreen(
      {Key? key, required this.controller, required this.chessGame})
      : super(key: key);

  @override
  ConsumerState<BlindChessScreen> createState() => _BlindChessScreenState();
}

class _BlindChessScreenState extends ConsumerState<BlindChessScreen>
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

  String _moveToLongString(MoveMeta meta) {
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
        pieceName = '';
        break;
      default:
        break;
    }

    final col = meta.move?.to != null ? meta.move!.to % 8 : 0;
    final row = meta.move?.to != null ? (meta.move!.to ~/ 8) : 0;
    final f = String.fromCharCode('a'.codeUnitAt(0) + col);
    final r = (8 - row).toString();
    final toSq = '$f$r';

    if (pieceName.isEmpty) {
      return toSq.toUpperCase();
    }
    return '$pieceName ${toSq.toUpperCase()}';
  }

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

    // Parse the square to tile (a1=56, h8=7)
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
    if (_step == 0) return 'Select Piece';

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

  @override
  Widget build(BuildContext context) {
    final appModel = prov.Provider.of<AppModel>(context);
    final theme = appModel.theme;
    final peekState = ref.watch(peekingProvider);
    final isWhiteTurn = appModel.turn == Player.player1;
    final tokens =
        isWhiteTurn ? peekState.player1Tokens : peekState.player2Tokens;
    final moves = isWhiteTurn ? peekState.player1Moves : peekState.player2Moves;
    final frequency = peekState.peekFrequency;
    final moveCount = appModel.moveMetaList.length;
    final moveNumber = (moveCount ~/ 2) + 1;
    final hasTimer = appModel.timeLimit > 0;

    final bgGrad = theme.background ??
        const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0F0C), Color(0xFF111A14)],
        );

    final playerColorSuffix = isWhiteTurn ? 'white' : 'black';
    final formattedTheme = formatPieceTheme(appModel.prefs.pieceTheme);

    return Container(
      decoration: BoxDecoration(gradient: bgGrad),
      child: SafeArea(
        child: Column(
          children: [
            // ── Top Bar with Exit/Back Button ──────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(
                    Icons.arrow_back_ios_new,
                    size: 20,
                    color: theme.lightTile,
                  ),
                ),
              ),
            ),
            // ── Clock bar ──────────────────────────────────────────
            if (hasTimer) ...[
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    TimerWidget(
                      timeLeft: appModel.player1TimeLeft,
                      delayLeft: appModel.timerService.player1DelayLeft,
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
                    const SizedBox(width: 12),
                    TimerWidget(
                      timeLeft: appModel.player2TimeLeft,
                      delayLeft: appModel.timerService.player2DelayLeft,
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
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 10),
            ],

            // ── Mode badge + move counter ──────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.moveHint.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: theme.moveHint.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.visibility_off_rounded,
                            size: 14, color: theme.lightTile),
                        const SizedBox(width: 6),
                        Text(
                          'BLIND MODE',
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
                        isWhiteTurn ? '⬜ White to move' : '⬛ Black to move',
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

            const SizedBox(height: 20),

            // ── Move Input Readout ──────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GlassPanel(
                borderRadius: 18,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Column(
                  children: [
                    AnimatedBuilder(
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
                        _partialDisplay,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace',
                          letterSpacing: 3,
                          color: _showError
                              ? const Color(0xFFFF5252)
                              : const Color(0xFFE5E2E1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ── Main UI Area (depends on whose turn it is) ─────────────────
            Expanded(
              child: Builder(
                builder: (context) {
                  final isAIsTurn = appModel.playingWithAI &&
                      appModel.turn != appModel.playerSide;

                  if (isAIsTurn) {
                    return const Center(
                      child: Text(
                        'Engine Thinking...',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFC3C8C2),
                          letterSpacing: 2,
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: [
                      // ── Instruction Label ──────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 20),
                        child: Text(
                          _stepLabel(),
                          style: TextStyle(
                            color: theme.lightTile.withValues(alpha: 0.7),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),

                      // ── Input Grid or Animation ────────────────────────────────────────
                      if (_showOpponentMoveAnim)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 24.0),
                            child: Stack(
                              children: [
                                AnimatedBuilder(
                                  animation: _opponentMoveCtrl,
                                  builder: (context, child) {
                                    final animProgress =
                                        _opponentMoveCtrl.value;
                                    double slideProgress = 0.0;
                                    if (animProgress > 0.8) {
                                      slideProgress = Curves.easeInOut
                                          .transform(
                                              (animProgress - 0.8) / 0.2);
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
                      else
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _buildInputGrid(
                                theme, formattedTheme, playerColorSuffix),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // ── Action bar ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Back button
                  if (_step > 0)
                    _ActionBtn(
                      icon: Icons.backspace_outlined,
                      label: 'Back',
                      theme: theme,
                      onTap: _stepBack,
                    ),

                  const Spacer(),

                  // Resign button
                  _ActionBtn(
                    icon: Icons.flag_outlined,
                    label: 'Resign',
                    theme: theme,
                    colorOverride: Colors.redAccent,
                    onTap: () {
                      appModel.haptic.medium();
                      appModel.endGame(winner: oppositePlayer(appModel.turn));
                    },
                  ),

                  const SizedBox(width: 12),

                  // Peek button
                  _PeekButton(
                    theme: theme,
                    tokens: tokens,
                    moves: moves,
                    frequency: frequency,
                    onTap: () {
                      appModel.haptic.light();
                      widget.controller.peekBoard();
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Offstage Flame Game so that it continues to tick and process animations
            Offstage(
              offstage: true,
              child: SizedBox(
                width: 1,
                height: 1,
                child: GameWidget(game: widget.chessGame),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputGrid(
      AppTheme theme, String formattedTheme, String playerColorSuffix) {
    if (_step == 0) {
      // Piece Selection Grid
      final pieces = [
        ChessPieceType.king,
        ChessPieceType.queen,
        ChessPieceType.rook,
        ChessPieceType.bishop,
        ChessPieceType.knight,
        ChessPieceType.pawn
      ];
      return GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        physics: const NeverScrollableScrollPhysics(),
        children: pieces.map((p) {
          final pStr = pieceTypeToString(p);
          return _GridButton(
            theme: theme,
            onTap: () => _handlePieceSelected(p),
            child: Image.asset(
              'assets/images/pieces/$formattedTheme/${pStr}_$playerColorSuffix.png',
              width: 50,
              height: 50,
            ),
          );
        }).toList(),
      );
    } else if (_step == 1) {
      // File Selection (a-h)
      return _buildLettersGrid(
          theme, const ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'], _handleFile);
    } else if (_step == 2) {
      // Rank Selection (1-8)
      return _buildLettersGrid(
          theme, const ['1', '2', '3', '4', '5', '6', '7', '8'], _handleRank);
    } else if (_step == 3) {
      // Disambiguation Selection
      return GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        physics: const NeverScrollableScrollPhysics(),
        children: _candidates.map((c) {
          final sq = _tileToSquare(c.tile);
          return _GridButton(
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
                  width: 40,
                  height: 40,
                ),
                const SizedBox(height: 8),
                Text(
                  'on $sq',
                  style: TextStyle(
                    fontSize: 18,
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
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      physics: const NeverScrollableScrollPhysics(),
      children: items.map((label) {
        return _GridButton(
          theme: theme,
          onTap: () => onSelect(label),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: theme.lightTile,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _GridButton extends StatelessWidget {
  final AppTheme theme;
  final Widget child;
  final VoidCallback onTap;

  const _GridButton(
      {required this.theme, required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: theme.darkTile.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.lightTile.withValues(alpha: 0.22),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.lightTile.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final AppTheme theme;
  final VoidCallback onTap;
  final Color? colorOverride;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.theme,
    required this.onTap,
    this.colorOverride,
  });

  @override
  Widget build(BuildContext context) {
    final defaultColor = theme.lightTile;
    final color = colorOverride ?? defaultColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colorOverride != null
              ? colorOverride!.withValues(alpha: 0.1)
              : theme.moveHint.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
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

class _PeekButton extends StatelessWidget {
  final AppTheme theme;
  final int tokens;
  final int moves;
  final int frequency;
  final VoidCallback onTap;

  const _PeekButton({
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
      text = 'Peek ($tokens)';
    } else {
      text = 'Peek ($moves/$frequency)';
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
                    Icon(Icons.visibility_outlined, size: 14, color: color),
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
