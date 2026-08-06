import 'dart:async';

import 'package:chess/chess.dart' as ch;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../logic/chess_game.dart';
import '../../../logic/game_analysis_cache_storage.dart';
import '../../../logic/game_controller.dart';
import '../../../logic/game_library_storage.dart';
import '../../../logic/move_calculation/move_classes/move.dart';
import '../../../logic/player_style_analyzer.dart';
import '../../../logic/stockfish_service.dart';
import '../../../model/app_model.dart';
import '../../../model/game_analysis_models.dart';
import '../../../model/player.dart';
import '../chess_view/chess_board_widget.dart';

/// Full move-by-move game analysis page.
/// Adapted from MoveLab's AnalysisPage (line 4188) and FreeAnalysisPage (line 4894).
/// Uses a custom FEN-based chess board renderer (no external package needed).
class GameAnalysisPage extends StatefulWidget {
  final GameEntry? game;
  final String? pgn;
  final String? fen;

  const GameAnalysisPage({Key? key, this.game, this.pgn, this.fen})
      : super(key: key);

  @override
  State<GameAnalysisPage> createState() => _GameAnalysisPageState();
}

class _GameAnalysisPageState extends State<GameAnalysisPage> {
  final ScrollController _scrollController = ScrollController();

  // ── FEN / move state ──────────────────────────────────────────────────────
  List<String> _fenList = [];
  List<String> _allMoves = [];
  int _currentMoveIndex = 0;
  bool _whiteSideDown = true;

  // ── Engine state ──────────────────────────────────────────────────────────
  double _evalValue = 0.3;
  String _evalText = '+0.3';
  List<String> _topMoves = ['', '', ''];
  Timer? _evalDebounce;

  // ── Analysis ──────────────────────────────────────────────────────────────
  bool _isAnalyzing = false;
  bool _analysisDone = false;
  double _analysisProgress = 0.0;
  final Map<int, double> _cachedValues = {};
  final Map<int, String> _cachedTexts = {};
  final Map<int, List<String>> _cachedSuggestions = {};
  final Map<int, MoveAnalysis?> _moveAnalyses = {};
  double _whiteAccuracy = 0.0;
  double _blackAccuracy = 0.0;

  // ── Library ───────────────────────────────────────────────────────────────
  late final GameLibraryStorage _library;
  bool _isSaved = false;

  late final GameController _gameController;

  @override
  void initState() {
    super.initState();
    _gameController = GameController(context.read<AppModel>());
    _gameController.boardFrozen = false;
    _library = GameLibraryStorage()..load();
    _cachedValues[0] = 0.3;
    _cachedTexts[0] = '+0.3';
    _cachedSuggestions[0] = ['e2e4', 'd2d4', 'g1f3'];
    _generateAllFens();
    _isSaved = _library.isSaved(
      widget.game?.pgn ?? widget.pgn ?? '',
      widget.game?.moves ?? '',
    );
    _checkCacheAndLoad();
  }

  String _buildGameKey() {
    final movesStr = widget.game?.moves ?? '';
    final pgnStr = widget.game?.pgn ?? widget.pgn ?? '';
    final startFen = widget.fen ??
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    return '${startFen.trim()}_${movesStr.trim()}_${pgnStr.trim()}';
  }

  Future<void> _checkCacheAndLoad() async {
    final key = _buildGameKey();
    final cached = await GameAnalysisCacheStorage.getAnalysis(key);
    if (cached != null) {
      _cachedValues.addAll(cached.evalValues);
      _cachedTexts.addAll(cached.evalTexts);
      _cachedSuggestions.addAll(cached.evalSuggestions);
      _whiteAccuracy = cached.whiteAccuracy;
      _blackAccuracy = cached.blackAccuracy;
      _analysisDone = true;
      _reconstructMoveAnalyses();
      if (mounted) setState(() {});
    }
    _loadToIndex(_currentMoveIndex);
  }

  void _reconstructMoveAnalyses() {
    for (int i = 1; i < _fenList.length; i++) {
      if (_cachedValues.containsKey(i) && _cachedValues.containsKey(i - 1)) {
        final prevEval = _cachedValues[i - 1] ?? 0.0;
        final rawEval = _cachedValues[i] ?? 0.0;
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
          alternatives: [],
          isWhiteMove: isWhiteMove,
          isMateFound: _cachedTexts[i]?.contains('M') ?? false,
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
      }
    }
  }

  @override
  void dispose() {
    _gameController.dispose();
    _evalDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── FEN Generation ────────────────────────────────────────────────────────

  void _generateAllFens() {
    _fenList = [];
    _allMoves = [];
    final chess = ch.Chess();

    if (widget.fen != null && widget.fen!.isNotEmpty) {
      chess.load(widget.fen!);
    }
    _fenList.add(chess.fen);

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
            RegExp(r'\[.*?\]|\{.*?\}|\([^)]*\)|(1-0|0-1|1\/2-1\/2|\*)|\d+\.+'),
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

  // ─── Navigation ────────────────────────────────────────────────────────────

  void _loadToIndex(int index) {
    if (index < 0 || index >= _fenList.length) return;
    _currentMoveIndex = index;
    _syncBoard();
    setState(() {});
    if (!_isAnalyzing) _startLiveEval(index);
  }

  void _syncBoard() {
    final fen = _fenList.isEmpty
        ? 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
        : _fenList[_currentMoveIndex];
    _gameController.loadFEN(fen);

    _gameController.selectedPiece = null;
    _gameController.validMoves = [];
    _gameController.warningTile = null;

    if (_currentMoveIndex > 0 && _currentMoveIndex <= _allMoves.length) {
      final moveStr = _allMoves[_currentMoveIndex - 1];
      if (moveStr.length >= 4) {
        try {
          final fileFrom = moveStr.codeUnitAt(0) - 97;
          final rankFrom = int.parse(moveStr[1]) - 1;
          final sqFrom = (7 - rankFrom) * 8 + fileFrom;

          final fileTo = moveStr.codeUnitAt(2) - 97;
          final rankTo = int.parse(moveStr[3]) - 1;
          final sqTo = (7 - rankTo) * 8 + fileTo;

          _gameController.latestMove = Move(sqFrom, sqTo);
        } catch (_) {
          _gameController.latestMove = null;
        }
      } else {
        _gameController.latestMove = null;
      }
    } else {
      _gameController.latestMove = null;
    }

    context.read<AppModel>().playerSide =
        _whiteSideDown ? Player.player1 : Player.player2;
    _gameController.onSnapSprites?.call(snap: true);
  }

  void _goFirst() {
    _loadToIndex(0);
    context.read<AppModel>().haptic.light();
    context.read<AppModel>().audio.playMovedSound();
  }

  void _goPrev() {
    if (_currentMoveIndex > 0) {
      _loadToIndex(_currentMoveIndex - 1);
      context.read<AppModel>().haptic.light();
      context.read<AppModel>().audio.playMovedSound();
    }
  }

  void _goNext() {
    if (_currentMoveIndex < _fenList.length - 1) {
      _loadToIndex(_currentMoveIndex + 1);
      context.read<AppModel>().haptic.light();
      context.read<AppModel>().audio.playMovedSound();
    }
  }

  void _goLast() {
    _loadToIndex(_fenList.length - 1);
    context.read<AppModel>().haptic.light();
    context.read<AppModel>().audio.playMovedSound();
  }

  // ─── Engine Eval ──────────────────────────────────────────────────────────

  void _startLiveEval(int forIndex) {
    if (_fenList.isEmpty || forIndex >= _fenList.length) return;
    final fen = _fenList[forIndex];
    _evalDebounce?.cancel();
    _evalDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final result = await StockfishService().evaluateFenForAnalysis(fen);
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
          } else {
            bAccTotal += acc;
            bCount++;
          }
        }
      } catch (_) {}
      if (mounted) {
        setState(() => _analysisProgress = i / (_fenList.length - 1));
      }
      await Future.delayed(const Duration(milliseconds: 30));
    }
    _whiteAccuracy = wCount > 0 ? wAccTotal / wCount : 0;
    _blackAccuracy = bCount > 0 ? bAccTotal / bCount : 0;

    // Save to cache
    final key = _buildGameKey();
    GameAnalysisCacheStorage.addAnalysis(
      CachedGameAnalysis(
        gameKey: key,
        evalValues: Map<int, double>.from(_cachedValues),
        evalTexts: Map<int, String>.from(_cachedTexts),
        evalSuggestions: Map<int, List<String>>.from(_cachedSuggestions),
        whiteAccuracy: _whiteAccuracy,
        blackAccuracy: _blackAccuracy,
      ),
    );

    if (mounted) {
      setState(() {
        _isAnalyzing = false;
        _analysisDone = true;
        _analysisProgress = 1.0;
      });
      _loadToIndex(_currentMoveIndex);
    }
  }

  // ─── Library ──────────────────────────────────────────────────────────────

  Future<void> _toggleLibrary() async {
    final g = widget.game;
    final pgn = g?.pgn ?? widget.pgn ?? '';
    final moves = g?.moves ?? '';
    if (pgn.isEmpty && moves.isEmpty) return;
    if (_isSaved) {
      final ids = _library.games
          .where((s) => pgn.isNotEmpty ? s.pgn == pgn : s.moves == moves)
          .map((s) => s.id)
          .toList();
      for (final id in ids) {
        await _library.remove(id);
      }
      if (mounted) setState(() => _isSaved = false);
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
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

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

  String _qualitySymbol(String label) {
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
    return Consumer<AppModel>(
      builder: (context, appModel, _) {
        final theme = appModel.theme;
        final accent = theme.lightTile;
        final currentAnalysis = _moveAnalyses[_currentMoveIndex];
        return Scaffold(
          backgroundColor: const Color(0xFF0E1420),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0E1420),
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.pop(context),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: accent,
                size: 20,
              ),
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
              IconButton(
                onPressed: () =>
                    setState(() => _whiteSideDown = !_whiteSideDown),
                icon: Icon(
                  Icons.swap_vert_rounded,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                tooltip: 'Rotate board',
              ),
              IconButton(
                onPressed: _toggleLibrary,
                icon: Icon(
                  _isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline,
                  color:
                      _isSaved ? accent : Colors.white.withValues(alpha: 0.7),
                ),
              ),
              if (widget.game?.pgn != null || widget.pgn != null)
                IconButton(
                  onPressed: () {
                    // Share via clipboard — share_plus not available in this project
                    // Users can copy from the move list
                  },
                  icon: Icon(
                    Icons.share_rounded,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              // ── Eval bar ─────────────────────────────────────────────────
              _EvalBar(evalValue: _evalValue),

              // ── Chess board ───────────────────────────────────────────────
              AspectRatio(
                aspectRatio: 1.0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Center(
                    child: ChessBoardWidget(
                      appModel,
                      ChessGame(_gameController, appModel),
                    ),
                  ),
                ),
              ),

              // ── Navigation bar ────────────────────────────────────────────
              _buildNavBar(accent),

              // ── Scrollable panel ──────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (currentAnalysis != null)
                        _buildQualityRow(currentAnalysis),
                      const SizedBox(height: 12),
                      _buildEngineMoves(accent),
                      const SizedBox(height: 16),
                      if (!_analysisDone) _buildAnalyseBtn(accent),
                      if (_isAnalyzing) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _analysisProgress,
                            minHeight: 4,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.08,
                            ),
                            valueColor: AlwaysStoppedAnimation(accent),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Analysing… ${(_analysisProgress * 100).toInt()}%',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 11,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                      if (_analysisDone) _buildAccuracySummary(accent),
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

  // ─── Nav Bar ──────────────────────────────────────────────────────────────

  Widget _buildNavBar(Color accent) {
    bool hasPrev = _currentMoveIndex > 0;
    bool hasNext = _currentMoveIndex < _fenList.length - 1;
    Color btn(bool a) => a ? accent : Colors.white.withValues(alpha: 0.2);

    return Container(
      height: 52,
      color: const Color(0xFF111928),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              _evalText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
              ),
            ),
          ),
          IconButton(
            onPressed: hasPrev ? _goFirst : null,
            icon: Icon(Icons.first_page_rounded, color: btn(hasPrev)),
          ),
          IconButton(
            onPressed: hasPrev ? _goPrev : null,
            icon: Icon(
              Icons.chevron_left_rounded,
              color: btn(hasPrev),
              size: 28,
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '$_currentMoveIndex/${_allMoves.length}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
                fontFamily: 'Inter',
              ),
            ),
          ),
          IconButton(
            onPressed: hasNext ? _goNext : null,
            icon: Icon(
              Icons.chevron_right_rounded,
              color: btn(hasNext),
              size: 28,
            ),
          ),
          IconButton(
            onPressed: hasNext ? _goLast : null,
            icon: Icon(Icons.last_page_rounded, color: btn(hasNext)),
          ),
        ],
      ),
    );
  }

  // ─── Engine Moves ─────────────────────────────────────────────────────────

  Widget _buildEngineMoves(Color accent) {
    final visible = _topMoves.where((m) => m.isNotEmpty).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Engine suggestions',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: visible.take(3).map((m) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: accent.withValues(alpha: 0.3),
                  width: 0.5,
                ),
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
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─── Quality Row ──────────────────────────────────────────────────────────

  Widget _buildQualityRow(MoveAnalysis a) {
    final c = _qualityColor(a.qualityLabel);
    final sym = _qualitySymbol(a.qualityLabel);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.withValues(alpha: 0.4), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sym.isNotEmpty) ...[
                Text(
                  sym,
                  style: TextStyle(
                    color: c,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                a.qualityLabel,
                style: TextStyle(
                  color: c,
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
          'Acc: ${a.accuracy.toStringAsFixed(0)}%',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 12,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }

  // ─── Analyse Button ───────────────────────────────────────────────────────

  Widget _buildAnalyseBtn(Color accent) {
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
              const Icon(
                Icons.analytics_rounded,
                color: Colors.white,
                size: 18,
              ),
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
            child: _accChip('White', _whiteAccuracy, const Color(0xFFF0D9B5)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _accChip('Black', _blackAccuracy, const Color(0xFF8B7355)),
          ),
        ],
      ),
    );
  }

  Widget _accChip(String label, double acc, Color col) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
            fontFamily: 'Inter',
          ),
        ),
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
        Text(
          'Accuracy',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 10,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }

  // ─── Move List ────────────────────────────────────────────────────────────

  Widget _buildMoveList(Color accent) {
    if (_allMoves.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Moves',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          children: List.generate(_allMoves.length, (i) {
            final moveNum = i ~/ 2 + 1;
            final isWhite = i % 2 == 0;
            final fenIdx = i + 1;
            final isActive = _currentMoveIndex == fenIdx;
            final analysis = _moveAnalyses[fenIdx];
            final qualCol = analysis != null
                ? _qualityColor(analysis.qualityLabel)
                : Colors.transparent;

            return GestureDetector(
              onTap: () => _loadToIndex(fenIdx),
              child: Container(
                margin: const EdgeInsets.only(bottom: 4, right: 2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive
                      ? accent.withValues(alpha: 0.22)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: isActive
                      ? Border.all(
                          color: accent.withValues(alpha: 0.5),
                          width: 0.5,
                        )
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isWhite)
                      Text(
                        '$moveNum. ',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 12,
                          fontFamily: 'Inter',
                        ),
                      ),
                    Text(
                      _allMoves[i],
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.white70,
                        fontSize: 13,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w400,
                        fontFamily: 'Inter',
                      ),
                    ),
                    if (analysis != null && qualCol != Colors.transparent) ...[
                      const SizedBox(width: 3),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: qualCol,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ─── Eval Bar ─────────────────────────────────────────────────────────────────

class _EvalBar extends StatelessWidget {
  final double evalValue;
  const _EvalBar({required this.evalValue});

  @override
  Widget build(BuildContext context) {
    final clamped = evalValue.clamp(-8.0, 8.0);
    final whiteFrac = ((clamped + 8.0) / 16.0).clamp(0.08, 0.92);
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
}
