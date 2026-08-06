import 'dart:async';

import 'package:chess/chess.dart' as chess_engine;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../logic/game_library_storage.dart';
import '../../../logic/player_style_analyzer.dart';
import '../../../logic/stockfish_service.dart';
import '../../../model/app_model.dart';
import '../../../model/app_themes.dart';
import '../../../model/game_analysis_models.dart';

/// Full move-by-move game analysis page.
/// Adapted from MoveLab's AnalysisPage (line 4188) and FreeAnalysisPage (line 4894).
/// Uses flutter_chess_board for the interactive board and our existing StockfishService
/// for evaluation.
class GameAnalysisPage extends StatefulWidget {
  final GameEntry? game;

  /// For PGN/FEN based analysis (no GameEntry available yet).
  final String? pgn;
  final String? fen;

  const GameAnalysisPage({Key? key, this.game, this.pgn, this.fen})
      : super(key: key);

  @override
  State<GameAnalysisPage> createState() => _GameAnalysisPageState();
}

class _GameAnalysisPageState extends State<GameAnalysisPage> {
  late final ChessBoardController _boardController;
  final ScrollController _scrollController = ScrollController();

  // ── Move / FEN state ──────────────────────────────────────────────────────
  List<String> _fenList = [];
  List<String> _allMoves = [];
  int _currentMoveIndex = 0;

  // ── Engine state ──────────────────────────────────────────────────────────
  double _evalValue = 0.3;
  String _evalText = '+0.3';
  List<String> _topMoves = ['', '', ''];
  bool _isEngineRunning = false;
  StreamSubscription<String>? _engineSub;
  Timer? _evalDebounce;

  // ── Analysis state ────────────────────────────────────────────────────────
  bool _isAnalyzing = false;
  bool _analysisDone = false;
  double _analysisProgress = 0.0;
  final Map<int, double> _cachedValues = {};
  final Map<int, String> _cachedTexts = {};
  final Map<int, List<String>> _cachedSuggestions = {};
  final Map<int, MoveAnalysis?> _moveAnalyses = {};
  double _whiteAccuracy = 0.0;
  double _blackAccuracy = 0.0;

  // ── Library state ─────────────────────────────────────────────────────────
  late final GameLibraryStorage _library;
  bool _isSaved = false;

  // ── Board orientation ─────────────────────────────────────────────────────
  PlayerColor _orientation = PlayerColor.white;

  @override
  void initState() {
    super.initState();
    _boardController = ChessBoardController();
    _library = GameLibraryStorage()..load();

    _cachedValues[0] = 0.3;
    _cachedTexts[0] = '+0.3';
    _cachedSuggestions[0] = ['e2e4', 'd2d4', 'g1f3'];

    _generateAllFens();
    _isSaved = _library.isSaved(
      widget.game?.pgn ?? widget.pgn ?? '',
      widget.game?.moves ?? '',
    );
    _loadBoardToIndex(_currentMoveIndex);
  }

  @override
  void dispose() {
    _evalDebounce?.cancel();
    _engineSub?.cancel();
    _boardController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── FEN Generation ────────────────────────────────────────────────────────

  void _generateAllFens() {
    _fenList = [];
    _allMoves = [];
    final chess = chess_engine.Chess();
    _fenList.add(chess.fen);

    // 1. FEN mode
    if (widget.fen != null && widget.fen!.isNotEmpty) {
      chess.load(widget.fen!);
      _fenList = [chess.fen];
      return;
    }

    // 2. PGN or game moves
    final movesStr = widget.game?.moves ?? '';
    final pgnStr = widget.game?.pgn ?? widget.pgn ?? '';

    if (movesStr.isNotEmpty) {
      for (final m in movesStr.trim().split(RegExp(r'\s+'))) {
        if (m.isEmpty) continue;
        bool ok = false;
        if (m.length >= 4) {
          final data = <String, dynamic>{
            'from': m.substring(0, 2),
            'to': m.substring(2, 4),
          };
          if (m.length > 4) data['promotion'] = m[4].toLowerCase();
          ok = chess.move(data);
        }
        if (!ok) ok = chess.move(m);
        if (ok) {
          _fenList.add(chess.fen);
          _allMoves.add(m);
        }
      }
    } else if (pgnStr.isNotEmpty) {
      final cleaned = pgnStr.replaceAll('\n', ' ').replaceAll(
            RegExp(
                r'\[.*?\]|\{.*?\}|\([^)]*\)|(1-0|0-1|1\/2-1\/2|\*)|(\d+\.+)'),
            ' ',
          );
      for (final san
          in cleaned.split(RegExp(r'\s+')).where((s) => s.isNotEmpty)) {
        if (chess.move(san)) {
          _fenList.add(chess.fen);
          _allMoves.add(san);
        }
      }
    }
  }

  // ─── Board Navigation ──────────────────────────────────────────────────────

  void _loadBoardToIndex(int index) {
    if (index < 0 || index >= _fenList.length) return;
    _currentMoveIndex = index;
    _boardController.loadFen(_fenList[index]);

    if (_cachedValues.containsKey(index)) {
      _evalValue = _cachedValues[index]!;
      _evalText = _cachedTexts[index]!;
      _topMoves = _cachedSuggestions[index] ?? ['', '', ''];
    } else {
      _evalText = 'Analyzing…';
      _topMoves = ['', '', ''];
    }
    setState(() {});

    if (!_isAnalyzing) _startLiveEval(index);
  }

  void _goFirst() => _loadBoardToIndex(0);
  void _goPrev() {
    if (_currentMoveIndex > 0) _loadBoardToIndex(_currentMoveIndex - 1);
  }

  void _goNext() {
    if (_currentMoveIndex < _fenList.length - 1) {
      _loadBoardToIndex(_currentMoveIndex + 1);
    }
  }

  void _goLast() => _loadBoardToIndex(_fenList.length - 1);

  // ─── Engine Evaluation ────────────────────────────────────────────────────

  void _startLiveEval(int forIndex) {
    if (_fenList.isEmpty || forIndex >= _fenList.length) return;
    final fen = _fenList[forIndex];

    // Use our app's StockfishService via stdin/stdout for live analysis.
    // We build a simple completer-based single-shot eval.
    _evalDebounce?.cancel();
    _evalDebounce = Timer(const Duration(milliseconds: 200), () async {
      final sf = StockfishService();
      try {
        final result = await sf.evaluateFenForAnalysis(fen);
        if (!mounted || _currentMoveIndex != forIndex) return;

        final rawEval = (result['best_eval'] as double?) ?? 0.0;
        final isMate = (result['is_mate'] as bool?) ?? false;
        final suggs = List<String>.from(result['suggestions'] as List? ?? []);

        final text = isMate || rawEval.abs() > 14.0
            ? (rawEval > 0 ? '+M' : '-M')
            : (rawEval > 0
                ? '+${rawEval.toStringAsFixed(1)}'
                : rawEval.toStringAsFixed(1));

        _cachedValues[forIndex] = rawEval;
        _cachedTexts[forIndex] = text;
        _cachedSuggestions[forIndex] = suggs;

        if (mounted) {
          setState(() {
            _evalValue = rawEval;
            _evalText = text;
            _topMoves = suggs.take(3).toList();
          });
        }
      } catch (_) {}
    });
  }

  // ─── Full Game Analysis ────────────────────────────────────────────────────

  Future<void> _analyzeFullGame() async {
    if (_isAnalyzing || _fenList.length < 2) return;
    setState(() {
      _isAnalyzing = true;
      _analysisDone = false;
      _analysisProgress = 0.0;
    });

    double wAccTotal = 0, bAccTotal = 0;
    int wCount = 0, bCount = 0;
    final whiteMoveStats = <String, int>{
      'brilliant': 0,
      'great': 0,
      'best': 0,
      'excellent': 0,
      'good': 0,
      'inaccuracy': 0,
      'mistake': 0,
      'blunder': 0,
    };
    final blackMoveStats = Map<String, int>.from(whiteMoveStats);

    final sf = StockfishService();

    for (int i = 0; i < _fenList.length; i++) {
      if (!mounted) break;
      try {
        final result = await sf.evaluateFenForAnalysis(_fenList[i]);
        final rawEval = (result['best_eval'] as double?) ?? 0.0;
        final isMate = (result['is_mate'] as bool?) ?? false;
        final suggs = List<String>.from(result['suggestions'] as List? ?? []);
        final alts = List<double>.from(result['alternatives'] as List? ?? []);

        _cachedValues[i] = rawEval;
        _cachedTexts[i] = isMate || rawEval.abs() > 14.0
            ? (rawEval > 0 ? '+M' : '-M')
            : (rawEval > 0
                ? '+${rawEval.toStringAsFixed(1)}'
                : rawEval.toStringAsFixed(1));
        _cachedSuggestions[i] = suggs;

        if (i > 0) {
          final prevEval = _cachedValues[i - 1] ?? 0.0;
          final isWhiteMove = (i - 1) % 2 == 0;
          final acc = AccuracyCalculator.calculateMoveAccuracy(
            prevEval,
            rawEval,
            isWhiteMove,
            false,
            false,
          );
          final label = AdvancedClassifier.classifyMove(
            bestEval: prevEval,
            playedEval: rawEval,
            accuracy: acc,
            alternatives: alts,
            isWhiteMove: isWhiteMove,
            isMateFound: isMate,
            sacrificeType: 0,
          );
          _moveAnalyses[i] = MoveAnalysis(
            bestEval: prevEval,
            playedEval: rawEval,
            accuracy: acc,
            qualityLabel: label,
            isBrilliant: AdvancedClassifier.isBrilliant(label),
            isGreat: AdvancedClassifier.isGreat(label),
          );

          if (isWhiteMove) {
            wAccTotal += acc;
            wCount++;
            _incrementMoveStats(whiteMoveStats, label);
          } else {
            bAccTotal += acc;
            bCount++;
            _incrementMoveStats(blackMoveStats, label);
          }
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _analysisProgress = i / (_fenList.length - 1);
        });
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }

    _whiteAccuracy = wCount > 0 ? wAccTotal / wCount : 0.0;
    _blackAccuracy = bCount > 0 ? bAccTotal / bCount : 0.0;

    if (mounted) {
      setState(() {
        _isAnalyzing = false;
        _analysisDone = true;
        _analysisProgress = 1.0;
      });
      _loadBoardToIndex(_currentMoveIndex);
    }
  }

  void _incrementMoveStats(Map<String, int> stats, String label) {
    if (label.startsWith('Brilliant'))
      stats['brilliant'] = (stats['brilliant'] ?? 0) + 1;
    else if (label.startsWith('Great'))
      stats['great'] = (stats['great'] ?? 0) + 1;
    else if (label == 'Best')
      stats['best'] = (stats['best'] ?? 0) + 1;
    else if (label == 'Excellent')
      stats['excellent'] = (stats['excellent'] ?? 0) + 1;
    else if (label == 'Good')
      stats['good'] = (stats['good'] ?? 0) + 1;
    else if (label.startsWith('Inaccuracy'))
      stats['inaccuracy'] = (stats['inaccuracy'] ?? 0) + 1;
    else if (label.startsWith('Mistake'))
      stats['mistake'] = (stats['mistake'] ?? 0) + 1;
    else if (label.startsWith('Blunder'))
      stats['blunder'] = (stats['blunder'] ?? 0) + 1;
  }

  // ─── Library ──────────────────────────────────────────────────────────────

  Future<void> _toggleLibrary() async {
    final g = widget.game;
    final pgn = g?.pgn ?? widget.pgn ?? '';
    final moves = g?.moves ?? '';
    if (pgn.isEmpty && moves.isEmpty) return;

    if (_isSaved) {
      final toRemove = _library.games
          .where((s) => pgn.isNotEmpty ? s.pgn == pgn : s.moves == moves)
          .map((s) => s.id)
          .toList();
      for (final id in toRemove) {
        await _library.remove(id);
      }
      if (mounted) setState(() => _isSaved = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed from library.')),
        );
      }
    } else {
      final entry = g ??
          GameEntry(
            platform: GamePlatform.local,
            white: 'White',
            black: 'Black',
            winner: 'draw',
            speed: 'classical',
            pgn: pgn,
            moves: moves,
          );
      await _library.add(SavedAnalysisGame.fromGameEntry(entry));
      if (mounted) setState(() => _isSaved = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved to library!'),
            backgroundColor: Color(0xFF5C6BC0),
          ),
        );
      }
    }
  }

  // ─── Share ────────────────────────────────────────────────────────────────

  Future<void> _sharePgn() async {
    final pgn = widget.game?.pgn ?? widget.pgn ?? '';
    if (pgn.isNotEmpty) {
      await Share.share(pgn, subject: 'Chess game PGN');
    }
  }

  // ─── Move quality colour ──────────────────────────────────────────────────

  Color _qualityColor(String label) {
    if (label.startsWith('Brilliant')) return const Color(0xFF29B6F6);
    if (label.startsWith('Great')) return const Color(0xFF26C6DA);
    if (label == 'Best') return const Color(0xFF66BB6A);
    if (label == 'Excellent') return const Color(0xFF9CCC65);
    if (label == 'Good') return const Color(0xFFD4E157);
    if (label.startsWith('Inaccuracy')) return const Color(0xFFFFCA28);
    if (label.startsWith('Mistake')) return const Color(0xFFFF7043);
    if (label.startsWith('Blunder')) return const Color(0xFFEF5350);
    return Colors.white54;
  }

  String _qualityIcon(String label) {
    if (label.startsWith('Brilliant')) return '!!';
    if (label.startsWith('Great')) return '!';
    if (label == 'Best') return '★';
    if (label == 'Excellent') return '✓';
    if (label == 'Good') return '·';
    if (label.startsWith('Inaccuracy')) return '?!';
    if (label.startsWith('Mistake')) return '?';
    if (label.startsWith('Blunder')) return '??';
    return '';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Selector<AppModel, AppTheme>(
      selector: (_, m) => m.theme,
      builder: (context, theme, _) {
        final accent = theme.lightTile;
        final currentAnalysis = _moveAnalyses[_currentMoveIndex];

        return Scaffold(
          backgroundColor: const Color(0xFF0E1420),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0E1420),
            foregroundColor: Colors.white,
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.pop(context),
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  color: accent, size: 20),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.game != null
                      ? '${widget.game!.white} vs ${widget.game!.black}'
                      : widget.fen != null
                          ? 'FEN Analysis'
                          : 'PGN Analysis',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
                if (widget.game != null)
                  Text(
                    '${widget.game!.platform.displayName}  •  ${widget.game!.speed}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontFamily: 'Inter',
                    ),
                  ),
              ],
            ),
            actions: [
              // Rotate board
              IconButton(
                onPressed: () => setState(() => _orientation =
                    _orientation == PlayerColor.white
                        ? PlayerColor.black
                        : PlayerColor.white),
                icon: Icon(Icons.swap_vert_rounded,
                    color: Colors.white.withValues(alpha: 0.7)),
                tooltip: 'Rotate board',
              ),
              // Save to library
              IconButton(
                onPressed: _toggleLibrary,
                icon: Icon(
                  _isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline,
                  color:
                      _isSaved ? accent : Colors.white.withValues(alpha: 0.7),
                ),
                tooltip: _isSaved ? 'Remove from library' : 'Save to library',
              ),
              // Share PGN
              if (widget.game?.pgn != null || widget.pgn != null)
                IconButton(
                  onPressed: _sharePgn,
                  icon: Icon(Icons.share_rounded,
                      color: Colors.white.withValues(alpha: 0.7)),
                  tooltip: 'Share PGN',
                ),
            ],
          ),
          body: Column(
            children: [
              // ── Eval bar ───────────────────────────────────────────────────
              _buildEvalBar(accent),

              // ── Chess board ────────────────────────────────────────────────
              AspectRatio(
                aspectRatio: 1.0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ChessBoard(
                    controller: _boardController,
                    boardColor: BoardColor.darkBrown,
                    boardOrientation: _orientation,
                  ),
                ),
              ),

              // ── Navigation bar ─────────────────────────────────────────────
              _buildNavBar(accent),

              // ── Scrollable bottom panel ────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Move quality label
                      if (currentAnalysis != null)
                        _buildQualityChip(currentAnalysis, accent),

                      const SizedBox(height: 10),

                      // Engine top moves
                      _buildEngineMoves(accent),

                      const SizedBox(height: 16),

                      // Analyse button
                      if (!_analysisDone) _buildAnalyseButton(accent),

                      // Progress
                      if (_isAnalyzing) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _analysisProgress,
                            minHeight: 4,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.1),
                            valueColor: AlwaysStoppedAnimation(accent),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Analysing… ${(_analysisProgress * 100).toInt()}%',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],

                      // Accuracy summary
                      if (_analysisDone) _buildAccuracySummary(accent),

                      // Move list
                      const SizedBox(height: 16),
                      _buildMoveList(accent),

                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Eval Bar ─────────────────────────────────────────────────────────────

  Widget _buildEvalBar(Color accent) {
    final double clamped = _evalValue.clamp(-8.0, 8.0);
    final double whiteFrac = ((clamped + 8.0) / 16.0).clamp(0.08, 0.92);
    return SizedBox(
      height: 6,
      child: Row(
        children: [
          Expanded(
            flex: (whiteFrac * 100).toInt(),
            child: Container(color: const Color(0xFFF0D9B5)),
          ),
          Expanded(
            flex: ((1 - whiteFrac) * 100).toInt(),
            child: Container(color: const Color(0xFF3D2B1F)),
          ),
        ],
      ),
    );
  }

  // ─── Nav Bar ──────────────────────────────────────────────────────────────

  Widget _buildNavBar(Color accent) {
    bool hasPrev = _currentMoveIndex > 0;
    bool hasNext = _currentMoveIndex < _fenList.length - 1;

    Color btnColor(bool active) =>
        active ? accent : Colors.white.withValues(alpha: 0.2);

    return Container(
      height: 52,
      color: const Color(0xFF111928),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Eval text
          SizedBox(
            width: 60,
            child: Text(
              _evalText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _evalValue >= 0 ? Colors.white : Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
              ),
            ),
          ),
          IconButton(
            onPressed: hasPrev ? _goFirst : null,
            icon: Icon(Icons.first_page_rounded, color: btnColor(hasPrev)),
          ),
          IconButton(
            onPressed: hasPrev ? _goPrev : null,
            icon: Icon(Icons.chevron_left_rounded,
                color: btnColor(hasPrev), size: 28),
          ),
          // Move counter
          SizedBox(
            width: 52,
            child: Text(
              '$_currentMoveIndex/${_allMoves.length}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 13,
                fontFamily: 'Inter',
              ),
            ),
          ),
          IconButton(
            onPressed: hasNext ? _goNext : null,
            icon: Icon(Icons.chevron_right_rounded,
                color: btnColor(hasNext), size: 28),
          ),
          IconButton(
            onPressed: hasNext ? _goLast : null,
            icon: Icon(Icons.last_page_rounded, color: btnColor(hasNext)),
          ),
        ],
      ),
    );
  }

  // ─── Engine Moves ─────────────────────────────────────────────────────────

  Widget _buildEngineMoves(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Engine suggestions',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: List.generate(
            _topMoves.length.clamp(0, 3),
            (i) {
              final m = i < _topMoves.length ? _topMoves[i] : '';
              if (m.isEmpty) return const SizedBox.shrink();
              return GestureDetector(
                onTap: () {
                  // Preview engine move on board
                  if (m.length >= 4) {
                    final chess = chess_engine.Chess();
                    chess.load(_fenList[_currentMoveIndex]);
                    final data = <String, dynamic>{
                      'from': m.substring(0, 2),
                      'to': m.substring(2, 4),
                    };
                    if (m.length > 4) data['promotion'] = m[4].toLowerCase();
                    if (chess.move(data)) {
                      _boardController.loadFen(chess.fen);
                    }
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: accent.withValues(alpha: 0.3), width: 0.5),
                  ),
                  child: Text(
                    m,
                    style: TextStyle(
                      color: accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── Quality Chip ─────────────────────────────────────────────────────────

  Widget _buildQualityChip(MoveAnalysis analysis, Color accent) {
    final color = _qualityColor(analysis.qualityLabel);
    final icon = _qualityIcon(analysis.qualityLabel);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon.isNotEmpty) ...[
                Text(icon,
                    style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                const SizedBox(width: 5),
              ],
              Text(
                analysis.qualityLabel,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Acc: ${analysis.accuracy.toStringAsFixed(0)}%',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 12,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }

  // ─── Analyse Button ───────────────────────────────────────────────────────

  Widget _buildAnalyseButton(Color accent) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton(
        onPressed: _isAnalyzing ? null : _analyzeFullGame,
        padding: EdgeInsets.zero,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: 0.85),
                accent.withValues(alpha: 0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.analytics_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Analyse Full Game',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Accuracy Summary ─────────────────────────────────────────────────────

  Widget _buildAccuracySummary(Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
              child:
                  _accChip('White', _whiteAccuracy, const Color(0xFFF0D9B5))),
          const SizedBox(width: 12),
          Expanded(
              child:
                  _accChip('Black', _blackAccuracy, const Color(0xFF8B7355))),
        ],
      ),
    );
  }

  Widget _accChip(String label, double acc, Color col) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
                fontFamily: 'Inter')),
        const SizedBox(height: 4),
        Text(
          '${acc.toStringAsFixed(0)}%',
          style: TextStyle(
            color: col,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            fontFamily: 'Inter',
          ),
        ),
        Text('Accuracy',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
                fontFamily: 'Inter')),
      ],
    );
  }

  // ─── Move List ────────────────────────────────────────────────────────────

  Widget _buildMoveList(Color accent) {
    if (_allMoves.isEmpty) return const SizedBox.shrink();
    final pairs = <List<_MovePair>>[];
    for (int i = 0; i < _allMoves.length; i += 2) {
      final white = _MovePair(
          index: i + 1, move: _allMoves[i], analysis: _moveAnalyses[i + 1]);
      final black = i + 1 < _allMoves.length
          ? _MovePair(
              index: i + 2,
              move: _allMoves[i + 1],
              analysis: _moveAnalyses[i + 2])
          : null;
      pairs.add([white, if (black != null) black]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Moves',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 8),
        ...pairs.asMap().entries.map((entry) {
          final pairIdx = entry.key;
          final pair = entry.value;
          return Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '${pairIdx + 1}.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              ...pair.map((mp) {
                final isActive = _currentMoveIndex == mp.index;
                final qualColor = mp.analysis != null
                    ? _qualityColor(mp.analysis!.qualityLabel)
                    : Colors.transparent;
                return GestureDetector(
                  onTap: () => _loadBoardToIndex(mp.index),
                  child: Container(
                    width: 70,
                    margin: const EdgeInsets.only(right: 4, bottom: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive
                          ? accent.withValues(alpha: 0.22)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: isActive
                          ? Border.all(
                              color: accent.withValues(alpha: 0.5), width: 0.5)
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            mp.move,
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.white70,
                              fontSize: 13,
                              fontWeight:
                                  isActive ? FontWeight.w700 : FontWeight.w400,
                              fontFamily: 'Inter',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (mp.analysis != null &&
                            qualColor != Colors.transparent)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(left: 3),
                            decoration: BoxDecoration(
                              color: qualColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        }),
      ],
    );
  }
}

// ─── Helper ──────────────────────────────────────────────────────────────────

class _MovePair {
  final int index;
  final String move;
  final MoveAnalysis? analysis;
  const _MovePair({required this.index, required this.move, this.analysis});
}
