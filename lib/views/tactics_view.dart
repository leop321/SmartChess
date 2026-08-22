import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/chess_board.dart';
import '../logic/chess_piece.dart';
import '../logic/move_calculation/move_classes/move.dart';
import '../logic/puzzle/fake_puzzle_repository.dart';
import '../logic/puzzle/uci_move_converter.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/player.dart';
import '../model/puzzle.dart';
import 'components/shared/glass_panel.dart';

// ── Shared DotGridPainter ──
class DotGridPainter extends CustomPainter {
  final Color color;
  const DotGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;
    const spacing = 20.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────
// Internal Puzzle Status Enum
// ─────────────────────────────────────────────────────

enum _PuzzleStatus {
  loading,
  showingOpponentMove,
  waitingForPlayerMove,
  correct,
  incorrect,
  solved,
  error,
}

// ─────────────────────────────────────────────────────
// Inline Puzzle Runner State (internal to tactics_view)
// ─────────────────────────────────────────────────────

/// Isolierter Puzzle-State ohne AppModel/GameController-Abhängigkeit.
/// Nutzt ChessBoard direkt (pure Dart-Klasse) für Zugausführung und Validierung.
///
/// Architektur-Entscheidung (dokumentiert): GameController erfordert AppModel
/// als Pflichtparameter und ist fest mit Timer, Audio, Haptic, AI, Save/Load
/// verdrahtet. AppModel-Konstruktor hat Seiteneffekte (Server-Warmup,
/// SharedPreferences). ChessBoard ist eine reine Dart-Klasse ohne solche
/// Abhängigkeiten und bietet alle benötigten Methoden: loadFEN, push, pop,
/// movesForPiece.
class _PuzzleRunnerState extends ChangeNotifier {
  final _board = ChessBoard();
  final _repo = FakePuzzleRepository();

  Puzzle? _currentPuzzle;
  Puzzle? get currentPuzzle => _currentPuzzle;

  _PuzzleStatus _status = _PuzzleStatus.loading;
  _PuzzleStatus get status => _status;

  List<int> validMovesForSelected = [];
  ChessPiece? selectedPiece;
  Move? latestMove;
  int? incorrectFromTile;
  int? incorrectToTile;
  String? errorMessage;
  ChessBoard get board => _board;

  int _moveIndex = 0;
  bool _disposed = false;
  Timer? _timer;

  void loadFirstPuzzle() {
    _reset();
    _doLoad();
  }

  Future<void> _doLoad() async {
    _setStatus(_PuzzleStatus.loading);
    try {
      final puzzle = await _repo.getNextPuzzle();
      if (_disposed) return;
      _currentPuzzle = puzzle;
      _board.loadFEN(puzzle.fen);
      _moveIndex = 0;
      // Gegnerzug nach 500ms
      _setStatus(_PuzzleStatus.showingOpponentMove);
      _timer = Timer(const Duration(milliseconds: 500), () {
        if (_disposed) return;
        _executeMove(puzzle.solutionMoves[0]);
        _moveIndex = 1;
        _setStatus(_PuzzleStatus.waitingForPlayerMove);
      });
    } catch (e) {
      if (_disposed) return;
      errorMessage = e.toString();
      _setStatus(_PuzzleStatus.error);
    }
  }

  void handleTap(int tile) {
    if (_status != _PuzzleStatus.waitingForPlayerMove) return;
    final puzzle = _currentPuzzle;
    if (puzzle == null) return;

    final tappedPiece = _board.tiles[tile];
    final playerSide = _getPlayerSide();

    if (selectedPiece == null) {
      if (tappedPiece != null && tappedPiece.player == playerSide) {
        selectedPiece = tappedPiece;
        validMovesForSelected = _board.movesForPiece(tappedPiece, legal: true);
        notifyListeners();
      }
      return;
    }

    if (tappedPiece == selectedPiece) {
      _clearSelection();
      return;
    }

    // Re-select eigene Figur
    if (tappedPiece != null &&
        tappedPiece.player == playerSide &&
        !validMovesForSelected.contains(tile)) {
      selectedPiece = tappedPiece;
      validMovesForSelected = _board.movesForPiece(tappedPiece, legal: true);
      notifyListeners();
      return;
    }

    if (validMovesForSelected.contains(tile)) {
      final move = Move(selectedPiece!.tile, tile);
      _clearSelection();
      _processPlayerMove(move, puzzle);
    } else {
      _clearSelection();
    }
  }

  void _processPlayerMove(Move move, Puzzle puzzle) {
    final expectedUci = puzzle.solutionMoves[_moveIndex];
    final playedUci = _moveToUci(move);

    _board.push(move);
    latestMove = move;

    if (playedUci == expectedUci) {
      _moveIndex++;
      _setStatus(_PuzzleStatus.correct);

      if (_moveIndex >= puzzle.solutionMoves.length) {
        _timer = Timer(const Duration(milliseconds: 400), () {
          if (!_disposed) _setStatus(_PuzzleStatus.solved);
        });
        return;
      }

      // Automatische Gegenantwort
      _timer = Timer(const Duration(milliseconds: 400), () {
        if (_disposed) return;
        _executeMove(puzzle.solutionMoves[_moveIndex]);
        _moveIndex++;
        if (_moveIndex >= puzzle.solutionMoves.length) {
          _setStatus(_PuzzleStatus.solved);
        } else {
          _setStatus(_PuzzleStatus.waitingForPlayerMove);
        }
      });
    } else {
      incorrectFromTile = move.from;
      incorrectToTile = move.to;
      _setStatus(_PuzzleStatus.incorrect);

      _timer = Timer(const Duration(milliseconds: 700), () {
        if (_disposed) return;
        _board.pop();
        latestMove = _board.moveStack.isNotEmpty
            ? _board.moveStack.last.move
            : null;
        incorrectFromTile = null;
        incorrectToTile = null;
        _setStatus(_PuzzleStatus.waitingForPlayerMove);
      });
    }
  }

  void _executeMove(String uci) {
    try {
      final move = uciToMove(uci, _board);
      _board.push(move);
      latestMove = move;
    } catch (e) {
      errorMessage = 'Fehler beim Ausführen von $uci: $e';
      _setStatus(_PuzzleStatus.error);
    }
  }

  Player _getPlayerSide() {
    if (_board.moveStack.isEmpty) return Player.player1;
    final lastMover = _board.moveStack.last.movedPiece?.player;
    return lastMover == Player.player1 ? Player.player2 : Player.player1;
  }

  void _clearSelection() {
    selectedPiece = null;
    validMovesForSelected = [];
    notifyListeners();
  }

  void _setStatus(_PuzzleStatus s) {
    _status = s;
    if (!_disposed) notifyListeners();
  }

  void _reset() {
    _timer?.cancel();
    _currentPuzzle = null;
    _moveIndex = 0;
    validMovesForSelected = [];
    selectedPiece = null;
    latestMove = null;
    incorrectFromTile = null;
    incorrectToTile = null;
    errorMessage = null;
  }

  String _moveToUci(Move move) {
    if (move.from == 60 && move.to == 63) return 'e1g1';
    if (move.from == 60 && move.to == 56) return 'e1c1';
    if (move.from == 4 && move.to == 7) return 'e8g8';
    if (move.from == 4 && move.to == 0) return 'e8c8';

    final fromRank = move.from ~/ 8;
    final fromFile = move.from % 8;
    final toRank = move.to ~/ 8;
    final toFile = move.to % 8;

    final fromStr =
        String.fromCharCode(fromFile + 97) + (8 - fromRank).toString();
    final toStr = String.fromCharCode(toFile + 97) + (8 - toRank).toString();
    String uci = '$fromStr$toStr';

    if (move.promotionType != ChessPieceType.promotion) {
      switch (move.promotionType) {
        case ChessPieceType.queen:
          uci += 'q';
        case ChessPieceType.rook:
          uci += 'r';
        case ChessPieceType.bishop:
          uci += 'b';
        case ChessPieceType.knight:
          uci += 'n';
        default:
          break;
      }
    }
    return uci;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────
// Main TacticsView
// ─────────────────────────────────────────────────────

class TacticsView extends StatelessWidget {
  const TacticsView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Selector<AppModel, AppTheme>(
      selector: (_, m) => m.theme,
      builder: (context, theme, _) {
        return Scaffold(
          body: Container(
            decoration: BoxDecoration(gradient: theme.background),
            child: Stack(
              children: [
                // 1. Dot Grid Background
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: DotGridPainter(
                        color: theme.lightTile.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                ),

                // 2. Ambient Glow Blob Top-Right
                Positioned(
                  top: 80,
                  right: -50,
                  child: RepaintBoundary(
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: theme.lightTile.withValues(alpha: 0.06),
                            blurRadius: 110,
                            spreadRadius: 25,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. Main Content
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        Text(
                          'TAKTIK',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: theme.lightTile.withValues(alpha: 0.6),
                            letterSpacing: 3.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Puzzles & Training',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFE5E2E1),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Expanded(child: _PuzzleSessionScreen()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────
// Puzzle Session Screen
// ─────────────────────────────────────────────────────

class _PuzzleSessionScreen extends StatefulWidget {
  const _PuzzleSessionScreen();

  @override
  State<_PuzzleSessionScreen> createState() => _PuzzleSessionScreenState();
}

class _PuzzleSessionScreenState extends State<_PuzzleSessionScreen> {
  late final _PuzzleRunnerState _runner;

  @override
  void initState() {
    super.initState();
    _runner = _PuzzleRunnerState();
    _runner.loadFirstPuzzle();
  }

  @override
  void dispose() {
    _runner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<_PuzzleRunnerState>.value(
      value: _runner,
      child: const _PuzzleSessionBody(),
    );
  }
}

class _PuzzleSessionBody extends StatelessWidget {
  const _PuzzleSessionBody();

  @override
  Widget build(BuildContext context) {
    final theme = context.select<AppModel, AppTheme>((m) => m.theme);

    return SingleChildScrollView(
      child: Column(
        children: [
          _StatusBanner(theme: theme),
          const SizedBox(height: 12),
          GlassPanel(
            padding: const EdgeInsets.all(4),
            borderRadius: 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _PuzzleBoardArea(),
            ),
          ),
          const SizedBox(height: 16),
          _RatingBadge(theme: theme),
          const SizedBox(height: 12),
          _NextPuzzleButton(theme: theme),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// Sub-Widgets
// ─────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final AppTheme theme;
  const _StatusBanner({required this.theme});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<_PuzzleRunnerState>();
    final (label, color, icon) = switch (state.status) {
      _PuzzleStatus.loading => (
          'Puzzle wird geladen …',
          theme.lightTile.withValues(alpha: 0.7),
          Icons.hourglass_empty_rounded,
        ),
      _PuzzleStatus.showingOpponentMove => (
          'Gegner zieht …',
          theme.moveHint,
          Icons.arrow_forward_rounded,
        ),
      _PuzzleStatus.waitingForPlayerMove => (
          'Dein Zug – finde den besten Zug!',
          theme.lightTile,
          Icons.psychology_rounded,
        ),
      _PuzzleStatus.correct => (
          'Richtig! ✓',
          const Color(0xFF4CAF50),
          Icons.check_circle_rounded,
        ),
      _PuzzleStatus.incorrect => (
          'Nicht korrekt – probiere es erneut',
          const Color(0xFFFF5555),
          Icons.close_rounded,
        ),
      _PuzzleStatus.solved => (
          'Puzzle gelöst! 🎉',
          const Color(0xFF4CAF50),
          Icons.emoji_events_rounded,
        ),
      _PuzzleStatus.error => (
          state.errorMessage ?? 'Fehler beim Laden',
          const Color(0xFFFF5555),
          Icons.error_outline_rounded,
        ),
    };

    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      borderRadius: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PuzzleBoardArea extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<_PuzzleRunnerState>();
    if (state.status == _PuzzleStatus.loading) {
      final theme = context.select<AppModel, AppTheme>((m) => m.theme);
      return AspectRatio(
        aspectRatio: 1.0,
        child: Container(
          color: theme.darkTile,
          child: Center(
            child: CircularProgressIndicator(
              color: theme.lightTile,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }
    return _InlinePuzzleBoard();
  }
}

/// Inline-Brett, das auf dem _PuzzleRunnerState aufbaut.
/// Delegiert Tap-Events an runner.handleTap und rendert per CustomPainter.
class _InlinePuzzleBoard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final runner = context.watch<_PuzzleRunnerState>();
    final theme = context.select<AppModel, AppTheme>((m) => m.theme);

    return AspectRatio(
      aspectRatio: 1.0,
      child: GestureDetector(
        onTapUp: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final localPos = box.globalToLocal(details.globalPosition);
          final tileSize = box.size.width / 8;
          final col = (localPos.dx / tileSize).floor().clamp(0, 7);
          final row = (localPos.dy / tileSize).floor().clamp(0, 7);
          runner.handleTap(row * 8 + col);
        },
        child: Stack(
          children: [
            // Board painter
            Positioned.fill(
              child: CustomPaint(
                painter: _InlineBoardPainter(
                  theme: theme,
                  tiles: runner.board.tiles,
                  validMoves: runner.validMovesForSelected,
                  selectedPiece: runner.selectedPiece,
                  latestMove: runner.latestMove,
                  incorrectFromTile: runner.incorrectFromTile,
                  incorrectToTile: runner.incorrectToTile,
                ),
              ),
            ),
            // Pieces overlay
            Positioned.fill(
              child: _InlinePiecesOverlay(
                tiles: runner.board.tiles,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineBoardPainter extends CustomPainter {
  final AppTheme theme;
  final List<ChessPiece?> tiles;
  final List<int> validMoves;
  final ChessPiece? selectedPiece;
  final Move? latestMove;
  final int? incorrectFromTile;
  final int? incorrectToTile;

  const _InlineBoardPainter({
    required this.theme,
    required this.tiles,
    required this.validMoves,
    this.selectedPiece,
    this.latestMove,
    this.incorrectFromTile,
    this.incorrectToTile,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tileSize = size.width / 8;
    final lightPaint = Paint()..color = theme.lightTile;
    final darkPaint = Paint()..color = theme.darkTile;
    final hintPaint = Paint()..color = theme.moveHint.withValues(alpha: 0.45);
    final selectedPaint = Paint()
      ..color = theme.latestMove.withValues(alpha: 0.5);
    final latestMovePaint = Paint()
      ..color = theme.latestMove.withValues(alpha: 0.3);
    final incorrectPaint = Paint()
      ..color = const Color(0xCCFF4444).withValues(alpha: 0.55);

    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        final tile = row * 8 + col;
        final rect = Rect.fromLTWH(
            col * tileSize, row * tileSize, tileSize, tileSize);
        final isLight = (row + col) % 2 == 0;
        canvas.drawRect(rect, isLight ? lightPaint : darkPaint);

        if (latestMove != null &&
            (tile == latestMove!.from || tile == latestMove!.to)) {
          canvas.drawRect(rect, latestMovePaint);
        }
        if (selectedPiece != null && tile == selectedPiece!.tile) {
          canvas.drawRect(rect, selectedPaint);
        }
        if (tile == incorrectFromTile || tile == incorrectToTile) {
          canvas.drawRect(rect, incorrectPaint);
        }
        if (validMoves.contains(tile)) {
          final piece = tiles[tile];
          if (piece != null) {
            canvas.drawCircle(
              rect.center,
              tileSize * 0.46,
              Paint()
                ..color = theme.moveHint.withValues(alpha: 0.5)
                ..style = PaintingStyle.stroke
                ..strokeWidth = tileSize * 0.08,
            );
          } else {
            canvas.drawCircle(rect.center, tileSize * 0.16, hintPaint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _InlineBoardPainter old) => true;
}

const _unicodePieces = {
  Player.player1: {
    ChessPieceType.king: '♔',
    ChessPieceType.queen: '♕',
    ChessPieceType.rook: '♖',
    ChessPieceType.bishop: '♗',
    ChessPieceType.knight: '♘',
    ChessPieceType.pawn: '♙',
  },
  Player.player2: {
    ChessPieceType.king: '♚',
    ChessPieceType.queen: '♛',
    ChessPieceType.rook: '♜',
    ChessPieceType.bishop: '♝',
    ChessPieceType.knight: '♞',
    ChessPieceType.pawn: '♟',
  },
};

class _InlinePiecesOverlay extends StatelessWidget {
  final List<ChessPiece?> tiles;
  const _InlinePiecesOverlay({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final tileSize = constraints.maxWidth / 8;
      final pieces = <Widget>[];
      for (int i = 0; i < 64; i++) {
        final piece = tiles[i];
        if (piece == null) continue;
        final row = i ~/ 8;
        final col = i % 8;
        final symbol = _unicodePieces[piece.player]?[piece.type] ?? '?';
        final textColor = piece.player == Player.player1
            ? const Color(0xFFF5F0E8)
            : const Color(0xFF1A1A1A);
        final shadowColor = piece.player == Player.player1
            ? const Color(0xFF2A2A2A)
            : const Color(0xFFF5F0E8);
        pieces.add(Positioned(
          left: col * tileSize,
          top: row * tileSize,
          width: tileSize,
          height: tileSize,
          child: Center(
            child: Text(
              symbol,
              style: TextStyle(
                fontSize: tileSize * 0.72,
                color: textColor,
                shadows: [
                  Shadow(
                    color: shadowColor.withValues(alpha: 0.8),
                    blurRadius: 2,
                    offset: const Offset(0.5, 0.5),
                  ),
                ],
              ),
            ),
          ),
        ));
      }
      return Stack(children: pieces);
    });
  }
}

class _RatingBadge extends StatelessWidget {
  final AppTheme theme;
  const _RatingBadge({required this.theme});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<_PuzzleRunnerState>();
    final puzzle = state.currentPuzzle;
    if (puzzle == null) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.bar_chart_rounded,
            size: 16, color: theme.lightTile.withValues(alpha: 0.6)),
        const SizedBox(width: 4),
        Text(
          'Rating: ${puzzle.rating}',
          style: TextStyle(
            fontSize: 13,
            color: theme.lightTile.withValues(alpha: 0.6),
            fontWeight: FontWeight.w500,
          ),
        ),
        if (puzzle.themes.isNotEmpty) ...[
          const SizedBox(width: 12),
          Icon(Icons.label_outline_rounded,
              size: 14, color: theme.lightTile.withValues(alpha: 0.4)),
          const SizedBox(width: 4),
          Text(
            puzzle.themes.take(2).join(', '),
            style: TextStyle(
              fontSize: 12,
              color: theme.lightTile.withValues(alpha: 0.4),
            ),
          ),
        ],
      ],
    );
  }
}

class _NextPuzzleButton extends StatelessWidget {
  final AppTheme theme;
  const _NextPuzzleButton({required this.theme});

  @override
  Widget build(BuildContext context) {
    final runner = context.watch<_PuzzleRunnerState>();
    if (runner.status != _PuzzleStatus.solved) return const SizedBox.shrink();

    return GestureDetector(
      onTap: runner.loadFirstPuzzle,
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        borderRadius: 30,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_forward_rounded,
                size: 18, color: Color(0xFFE5E2E1)),
            SizedBox(width: 8),
            Text(
              'Nächstes Puzzle',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFFE5E2E1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
