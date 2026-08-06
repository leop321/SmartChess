import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:chess/chess.dart' as ch;
import 'package:flutter/services.dart' show rootBundle;

import '../../model/lichess_puzzle.dart';
import '../../model/tactics_task.dart';
import '../lichess_puzzle_service.dart';
import '../stockfish_service.dart';
import 'tactics_task_provider.dart';

/// Provider for Anti-Tactics 2.0 (V2).
///
/// Rules:
/// 1. search_rating = user_elo + difficulty_offset + 200
/// 2. display_rating = search_rating - 200
/// 3. Ensures balanced color distribution (40-50% Black to move).
/// 4. Asynchronously generates and validates anti-tactics positions using Stockfish depth 12.
class LichessAntiTacticsV2Provider implements TacticsTaskProvider {
  final LichessPuzzleService api;
  final StockfishService _stockfish = StockfishService.instance;

  List<TacticsTask>? _cachedTasks;
  final Set<String> _sessionSeenIds = {};
  DateTime? _lastApiFetchTime;
  int _blackColorServedCount = 0;
  int _totalServedCount = 0;

  LichessAntiTacticsV2Provider({LichessPuzzleService? api})
      : api = api ?? LichessPuzzleService();

  Future<void> _ensureLoaded() async {
    if (_cachedTasks != null && _cachedTasks!.isNotEmpty) return;

    final List<TacticsTask> validTasks = [];

    try {
      final jsonString =
          await rootBundle.loadString('assets/data/anti_tactics_tasks.json');
      final List<dynamic> jsonList = jsonDecode(jsonString);

      for (final entry in jsonList) {
        try {
          final task = TacticsTask.fromJson(entry);
          if (task.version == 2 || task.mode == TacticsMode.antiTacticsV2) {
            validTasks.add(task);
          }
        } catch (e) {
          print(
              '[LichessAntiTacticsV2Provider] Error parsing anti-tactics task: $e');
        }
      }
    } catch (e) {
      print(
          '[LichessAntiTacticsV2Provider] Error loading anti_tactics_tasks.json: $e');
    }

    if (validTasks.isEmpty) {
      validTasks.addAll(await _getBuiltInMasterTasks());
    }

    _cachedTasks = validTasks;
    print(
        '[LichessAntiTacticsV2Provider] Successfully loaded ${_cachedTasks!.length} valid V2 tasks.');
  }

  @override
  Future<TacticsTask> fetchNextTask() async {
    await _ensureLoaded();
    final tasks = _cachedTasks!;

    _tryFetchRemotePuzzleInBackground();

    final userRating = await TacticsStorage.loadRating(mode: 'antiTacticsV2');
    final ratingOffset = await TacticsStorage.loadRatingOffset();

    // 1. Search rating = user_elo + offset + 200
    final searchRating = userRating + ratingOffset + 200;
    // 2. Display rating = search_rating - 200
    final displayRating = searchRating - 200;

    List<TacticsTask> eligiblePool = tasks.where((t) {
      if (_sessionSeenIds.contains(t.id)) return false;
      return (t.difficulty - searchRating).abs() <= 600;
    }).toList();

    if (eligiblePool.isEmpty) {
      eligiblePool =
          tasks.where((t) => !_sessionSeenIds.contains(t.id)).toList();
    }

    if (eligiblePool.isEmpty) {
      _sessionSeenIds.clear();
      eligiblePool = List.from(tasks);
    }

    // Color distribution balancing (target 40-50% Black to move)
    final double currentBlackRatio = _totalServedCount > 0
        ? _blackColorServedCount / _totalServedCount
        : 0.0;

    TacticsTask selected;
    if (currentBlackRatio < 0.40) {
      final blackPool =
          eligiblePool.where((t) => t.effectiveColorToMove == 'black').toList();
      if (blackPool.isNotEmpty) {
        selected = blackPool[Random().nextInt(blackPool.length)];
      } else {
        selected = eligiblePool[Random().nextInt(eligiblePool.length)];
      }
    } else {
      selected = eligiblePool[Random().nextInt(eligiblePool.length)];
    }

    _sessionSeenIds.add(selected.id);
    _totalServedCount++;
    if (selected.effectiveColorToMove == 'black') {
      _blackColorServedCount++;
    }

    // Return decorated task with search_rating & display_rating.
    // difficulty = the REAL puzzle rating so Elo deltas are meaningful.
    return TacticsTask(
      id: selected.id,
      fen: selected.fen,
      mode: TacticsMode.antiTacticsV2,
      antiTacticsType: AntiTacticsType.noWinningTactic,
      expectedMoves: selected.expectedMoves,
      difficulty: selected.effectiveDisplayRating,
      searchRating: searchRating,
      displayRating: displayRating,
      colorToMove: selected.effectiveColorToMove,
      type: 'antitactic',
      explanation: selected.explanation,
      explanationShort: selected.explanationShort,
      tags: selected.tags,
      themes: selected.themes,
      version: 2,
    );
  }

  @override
  Future<TacticsTask> fetchTaskById(String id) async {
    await _ensureLoaded();
    final tasks = _cachedTasks!;
    return tasks.firstWhere(
      (t) => t.id == id,
      orElse: () => tasks[0],
    );
  }

  void _tryFetchRemotePuzzleInBackground() {
    final now = DateTime.now();
    if (_lastApiFetchTime != null &&
        now.difference(_lastApiFetchTime!).inSeconds < 4) {
      return;
    }
    _lastApiFetchTime = now;

    Future(() async {
      try {
        final puzzle = await api.fetchNextPuzzle();
        final task = await _tryCreateAntiTacticV2Task(puzzle);
        if (task != null && _cachedTasks != null) {
          _cachedTasks!.add(task);
        }
      } catch (_) {}
    });
  }

  Future<TacticsTask?> _tryCreateAntiTacticV2Task(LichessPuzzle puzzle) async {
    ch.Chess? board;
    try {
      if (puzzle.fen.isEmpty) return null;
      board = ch.Chess.fromFEN(puzzle.fen);
      if (board.in_check || board.in_checkmate) return null;
    } catch (_) {
      return null;
    }

    final fen = board.fen;
    final isEqual = await _isEqualPosition(fen);
    if (!isEqual) return null;

    final colorToMove = board.turn == ch.Color.WHITE ? 'white' : 'black';

    return TacticsTask(
      id: 'v2_${puzzle.id}',
      fen: fen,
      mode: TacticsMode.antiTacticsV2,
      antiTacticsType: AntiTacticsType.noWinningTactic,
      expectedMoves: const [],
      difficulty: puzzle.rating,
      searchRating: puzzle.rating + 200,
      displayRating: puzzle.rating,
      colorToMove: colorToMove,
      type: 'antitactic',
      themes: puzzle.themes,
      explanation:
          'Verhindere die gegnerische Taktik durch Vorbeugung (Rating ${puzzle.rating}).',
      explanationShort: 'Anti-Taktik V2 (Rating ${puzzle.rating})',
      version: 2,
    );
  }

  Future<bool> _isEqualPosition(String fen) async {
    final matEval = _calculateMaterialBalance(fen);
    if (matEval.abs() > 1.8) return false;

    try {
      final board = ch.Chess.fromFEN(fen);
      if (board.in_check || board.in_checkmate) return false;

      final res = await _stockfish.evaluateFenForAnalysis(fen,
          depth: 12, timeoutMs: 2500);
      final eval = (res['best_eval'] as num?)?.toDouble() ?? 0.0;
      final isMate = res['is_mate'] as bool? ?? false;
      if (isMate) return false;
      return eval.abs() <= 1.5;
    } catch (_) {
      return matEval.abs() <= 1.5;
    }
  }

  double _calculateMaterialBalance(String fen) {
    final placement = fen.split(' ')[0];
    double balance = 0.0;
    for (int i = 0; i < placement.length; i++) {
      final char = placement[i];
      switch (char) {
        case 'P':
          balance += 1.0;
          break;
        case 'N':
          balance += 3.0;
          break;
        case 'B':
          balance += 3.0;
          break;
        case 'R':
          balance += 5.0;
          break;
        case 'Q':
          balance += 9.0;
          break;
        case 'p':
          balance -= 1.0;
          break;
        case 'n':
          balance -= 3.0;
          break;
        case 'b':
          balance -= 3.0;
          break;
        case 'r':
          balance -= 5.0;
          break;
        case 'q':
          balance -= 9.0;
          break;
      }
    }
    return balance;
  }

  Future<List<TacticsTask>> _getBuiltInMasterTasks() async {
    return [
      const TacticsTask(
        id: 'v2_master_2000_1',
        fen: '2r3k1/pp3p1p/4p1p1/q2pP3/b2P4/P1R1P3/1P1QB1PP/5RK1 w - - 3 20',
        mode: TacticsMode.antiTacticsV2,
        antiTacticsType: AntiTacticsType.winningTacticExists,
        expectedMoves: ['c3c8', 'd8c8', 'd2a5'],
        difficulty: 2000,
        searchRating: 2200,
        displayRating: 2000,
        colorToMove: 'white',
        type: 'antitactic',
        themes: ['discoveredAttack', 'tactics', 'queenWin'],
        explanation:
            'Abzugsschach Tc3-c8+ gewinnt die ungedeckte schwarze Dame auf a5!',
        explanationShort: 'Abzugsangriff (Rating 2000)',
        version: 2,
      ),
      const TacticsTask(
        id: 'v2_master_2000_2',
        fen: 'r1bqr1k1/ppp2ppp/2n2n2/3p4/3P4/2PB1N2/PP1Q1PPP/R3R1K1 w - - 0 1',
        mode: TacticsMode.antiTacticsV2,
        antiTacticsType: AntiTacticsType.winningTacticExists,
        expectedMoves: ['e1e8', 'd8e8', 'a1e1', 'e8d8', 'd3h7'],
        difficulty: 2000,
        searchRating: 2200,
        displayRating: 2000,
        colorToMove: 'white',
        type: 'antitactic',
        themes: ['greekGift', 'discoveredAttack', 'master'],
        explanation: 'Turmtausch auf e8 mit anschließendem Läuferopfer auf h7!',
        explanationShort: 'Griechengeschenk (Rating 2000)',
        version: 2,
      ),
    ];
  }
}
