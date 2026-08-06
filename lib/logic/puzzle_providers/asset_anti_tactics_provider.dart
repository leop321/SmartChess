import 'dart:convert';
import 'dart:math';

import 'package:chess/chess.dart' as ch;
import 'package:flutter/services.dart' show rootBundle;

import '../../model/anti_tactics_storage.dart';
import '../../model/lichess_puzzle.dart';
import '../../model/tactics_task.dart';
import 'tactics_task_provider.dart';

class AssetAntiTacticsProvider implements TacticsTaskProvider {
  final String assetPath;
  final TacticsMode targetMode;
  List<TacticsTask>? _cachedTasks;

  AssetAntiTacticsProvider({
    this.assetPath = 'assets/data/anti_tactics_tasks.json',
    this.targetMode = TacticsMode.antiTactics,
  });

  Future<void> _ensureLoaded() async {
    if (_cachedTasks != null) return;
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      final List<dynamic> jsonList = jsonDecode(jsonString);
      final List<TacticsTask> validTasks = [];

      for (int i = 0; i < jsonList.length; i++) {
        final entry = jsonList[i];
        final id = entry['id'] ?? 'unknown_$i';

        try {
          // Parse task
          final task = TacticsTask.fromJson(entry);

          // 1. Basic field checks
          if (task.id.trim().isEmpty) {
            print(
                '[AssetAntiTacticsProvider] WARNING: Task ignored due to empty ID.');
            continue;
          }
          if (task.fen.trim().isEmpty) {
            print(
                '[AssetAntiTacticsProvider] WARNING: Task "$id" ignored due to empty FEN.');
            continue;
          }

          // 2. Empty board FEN check
          final cleanFen = task.fen.trim();
          final fenParts = cleanFen.split(' ');
          if (fenParts.isEmpty || fenParts[0] == '8/8/8/8/8/8/8/8') {
            print(
                '[AssetAntiTacticsProvider] WARNING: Task "$id" ignored due to empty board FEN.');
            continue;
          }

          // 3. FEN structural validation via chess package
          final validation = ch.Chess.validate_fen(cleanFen);
          if (validation['valid'] != true) {
            print(
                '[AssetAntiTacticsProvider] WARNING: Task "$id" ignored due to invalid FEN structure: ${validation['error']}');
            continue;
          }

          // 4. Double check that we can instantiate it and that it has pieces
          final board = ch.Chess.fromFEN(cleanFen);
          int pieceCount = 0;
          for (final squareName in ch.Chess.SQUARES.keys) {
            if (board.get(squareName) != null) {
              pieceCount++;
            }
          }
          if (pieceCount == 0) {
            print(
                '[AssetAntiTacticsProvider] WARNING: Task "$id" ignored because board has 0 pieces.');
            continue;
          }

          // 5. Check difficulty & type validity
          if (task.difficulty <= 0) {
            print(
                '[AssetAntiTacticsProvider] WARNING: Task "$id" ignored due to invalid difficulty: ${task.difficulty}');
            continue;
          }
          if (task.antiTacticsType == null) {
            print(
                '[AssetAntiTacticsProvider] WARNING: Task "$id" ignored due to missing or invalid antiTacticsType.');
            continue;
          }

          // 6. Filter by target mode (V1 vs V2)
          bool isV2 = task.version == 2;
          if (targetMode == TacticsMode.antiTacticsV2 && !isV2) {
            continue;
          }
          if (targetMode == TacticsMode.antiTactics && isV2) {
            continue;
          }

          validTasks.add(task);
        } catch (e) {
          print(
              '[AssetAntiTacticsProvider] WARNING: Failed to parse task "$id": $e');
        }
      }

      if (validTasks.isEmpty && targetMode == TacticsMode.antiTacticsV2) {
        print(
            '[AssetAntiTacticsProvider] No V2 tasks found. Falling back to V1 tasks.');
        for (int i = 0; i < jsonList.length; i++) {
          final entry = jsonList[i];
          final id = entry['id'] ?? 'unknown_$i';
          try {
            final task = TacticsTask.fromJson(entry);
            if (task.id.trim().isEmpty || task.fen.trim().isEmpty) continue;
            final cleanFen = task.fen.trim();
            final fenParts = cleanFen.split(' ');
            if (fenParts.isEmpty || fenParts[0] == '8/8/8/8/8/8/8/8') continue;
            if (ch.Chess.validate_fen(cleanFen)['valid'] != true) continue;
            if (task.difficulty <= 0 || task.antiTacticsType == null) continue;
            if (task.version != 2) {
              validTasks.add(task);
            }
          } catch (e) {
            print(
                '[AssetAntiTacticsProvider] WARNING: Failed to parse fallback task "$id": $e');
          }
        }
      }

      if (validTasks.isEmpty) {
        throw Exception('All tasks in $assetPath failed validation.');
      }

      _cachedTasks = validTasks;
      print(
          '[AssetAntiTacticsProvider] Loaded ${_cachedTasks!.length} valid tasks from $assetPath.');
    } catch (e) {
      print(
          '[AssetAntiTacticsProvider] ERROR loading tasks: $e. Falling back to default valid task.');
      // Fallback auf eine vollkommen valide Taktikaufgabe (Könige + Turm, kein leeres Brett!)
      _cachedTasks = [
        const TacticsTask(
          id: 'fallback_default',
          fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
          mode: TacticsMode.antiTactics,
          antiTacticsType: AntiTacticsType.noWinningTactic,
          expectedMoves: [],
          difficulty: 1000,
          explanation: 'Standard-Startaufstellung als sicherer Fallback.',
          explanationShort: 'Fallback Startaufstellung',
        )
      ];
    }
  }

  final Set<String> _sessionSeenIds = {};

  @override
  Future<TacticsTask> fetchNextTask() async {
    await _ensureLoaded();
    final tasks = _cachedTasks!;

    final storage = AntiTacticsStorage.instance;
    await storage.init();

    final userRating = await TacticsStorage.loadRating(mode: targetMode.name);
    final ratingOffset = await TacticsStorage.loadRatingOffset();
    final targetRating = userRating + 200 + ratingOffset;

    List<TacticsTask> eligiblePool = [];
    String debugReason = "";

    // 1. Strict selection: exclude recent and session-seen, and filter by ELO window
    // We try ELO windows of +/- 200, 400, 600, 800, 1000 ELO to get closest matches
    for (int window in [200, 400, 600, 800, 1000]) {
      final pool = tasks.where((t) {
        if (storage.recentIds.contains(t.id)) return false;
        if (_sessionSeenIds.contains(t.id)) return false;
        final diff = (t.difficulty - targetRating).abs();
        return diff <= window;
      }).toList();

      if (pool.isNotEmpty) {
        eligiblePool = pool;
        debugReason = "Strict (window: +/-$window ELO, size: ${pool.length})";
        break;
      }
    }

    // Fallback 1: Allow session-seen, but NOT recent (filtered by ELO windows)
    if (eligiblePool.isEmpty) {
      _sessionSeenIds.clear(); // Reset session seen
      for (int window in [200, 400, 600, 800, 1000]) {
        final pool = tasks.where((t) {
          if (storage.recentIds.contains(t.id)) return false;
          final diff = (t.difficulty - targetRating).abs();
          return diff <= window;
        }).toList();

        if (pool.isNotEmpty) {
          eligiblePool = pool;
          debugReason =
              "Fallback 1 - Allowed session-seen (window: +/-$window ELO, size: ${pool.length})";
          break;
        }
      }
    }

    // Fallback 2: Allow recent, but NEVER the immediate last played (filtered by ELO windows)
    if (eligiblePool.isEmpty) {
      final lastId =
          storage.recentIds.isNotEmpty ? storage.recentIds.first : null;
      for (int window in [200, 400, 600, 800, 1000]) {
        final pool = tasks.where((t) {
          if (t.id == lastId) return false;
          final diff = (t.difficulty - targetRating).abs();
          return diff <= window;
        }).toList();

        if (pool.isNotEmpty) {
          eligiblePool = pool;
          debugReason =
              "Fallback 2 - Allowed recent (window: +/-$window ELO, size: ${pool.length})";
          break;
        }
      }
    }

    // Fallback 3: Absolutely no restrictions, get all tasks
    if (eligiblePool.isEmpty) {
      eligiblePool = List.from(tasks);
      debugReason = "Fallback 3 - No restrictions (size: ${tasks.length})";
      print(
          '[AntiTacticsProvider] WARNING: Pool is completely empty. Fallback 3 triggered. Dataset might be too small.');
    }

    // 2. Calculate weights for the eligible pool
    final Map<TacticsTask, double> weights = {};
    double totalWeight = 0.0;

    for (final task in eligiblePool) {
      double weight = 1.0;

      // We already heavily filtered, but we still prefer non-solved
      if (storage.solvedIds.contains(task.id)) {
        weight *= 0.1; // Much rarer if already solved
      }

      // Prefer tasks we failed before
      final wrongCount = storage.wrongCounts[task.id] ?? 0;
      if (wrongCount > 0) {
        weight *= (1.0 + wrongCount * 1.5); // Strong boost for wrong
      }

      // ELO proximity weighting
      final diffDelta = (task.difficulty - targetRating).abs();
      final proximityWeight =
          1000.0 / (1000.0 + diffDelta); // Closer delta -> higher weight
      weight *= proximityWeight;

      weights[task] = weight;
      totalWeight += weight;
    }

    TacticsTask? selectedTask;

    if (totalWeight <= 0) {
      selectedTask = eligiblePool[Random().nextInt(eligiblePool.length)];
    } else {
      // Weighted random selection
      double randomValue = Random().nextDouble() * totalWeight;
      for (final task in eligiblePool) {
        randomValue -= weights[task]!;
        if (randomValue <= 0) {
          selectedTask = task;
          break;
        }
      }
      selectedTask ??= eligiblePool.last;
    }

    _sessionSeenIds.add(selectedTask.id);

    // Debug Output
    print(
        '[AntiTacticsProvider] Selected: ${selectedTask.id} | Target ELO: $targetRating | Task ELO: ${selectedTask.difficulty} | Reason: $debugReason');

    return selectedTask;
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
}
