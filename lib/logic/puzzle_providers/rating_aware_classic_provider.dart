import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../model/lichess_puzzle.dart';
import '../../model/tactics_task.dart';
import '../lichess_puzzle_service.dart';
import 'tactics_task_provider.dart';

/// A [TacticsTaskProvider] for the classic tactics mode that selects puzzles
/// matching the player's current rating.
///
/// Strategy:
///  1. At startup, seeds a local pool from `assets/data/lichess_puzzles.json`.
///  2. Continuously fetches additional puzzles from the Lichess API in the
///     background, capping the pool at [_kMaxPoolSize].
///  3. On every [fetchNextTask] call, the puzzle whose [rating] is closest to
///     `userRating + ratingOffset` is selected and removed from the pool.
///     A background fetch is triggered if the pool drops below [_kRefillThreshold].
class RatingAwareClassicProvider implements TacticsTaskProvider {
  static const int _kMaxPoolSize = 100;
  static const int _kRefillThreshold = 15;

  final LichessPuzzleService _api;

  /// In-memory pool of available puzzles.
  final List<_PoolEntry> _pool = [];

  /// IDs seen in recent sessions (persisted across app restarts).
  final List<String> _seenIds = [];

  bool _seedLoaded = false;
  bool _fetchInProgress = false;

  RatingAwareClassicProvider({LichessPuzzleService? api})
      : _api = api ?? LichessPuzzleService();

  // ── Initialisation ──────────────────────────────────────────────────────────

  /// Loads the seed puzzles from the bundled asset (runs once).
  Future<void> _ensureSeedLoaded() async {
    if (_seedLoaded) return;
    _seedLoaded = true;
    try {
      final savedSeen =
          await TacticsStorage.loadRecentPuzzleIds(mode: 'classic');
      _seenIds.addAll(savedSeen);

      final jsonString =
          await rootBundle.loadString('assets/data/lichess_puzzles.json');
      final List<dynamic> jsonList = jsonDecode(jsonString);
      for (final entry in jsonList) {
        try {
          final puzzle = LichessPuzzle.fromJson(<String, dynamic>{
            'puzzle': <String, dynamic>{
              'id': entry['id'] as String?,
              'fen': entry['fen'] as String?,
              'solution': entry['solution'],
              'rating': entry['rating'],
              'themes': entry['themes'] ?? <dynamic>[],
              'lastMove': entry['lastMove'] as String?,
            },
          });
          _addToPool(puzzle);
        } catch (_) {
          // Skip malformed seed entries.
        }
      }
    } catch (e) {
      // Asset not found or corrupt — that is fine; the API will fill the pool.
      debugPrint('[RatingAwareClassicProvider] Seed load failed: $e');
    }
  }

  void _addToPool(LichessPuzzle puzzle) {
    if (!puzzle.isValidPuzzle) return;
    if (_pool.length >= _kMaxPoolSize) return;
    // Avoid duplicates.
    if (_pool.any((e) => e.puzzle.id == puzzle.id)) return;
    _pool.add(_PoolEntry(puzzle));
  }

  // ── Background fetching ──────────────────────────────────────────────────────

  void _triggerBackgroundFetch() {
    if (_fetchInProgress) return;
    _fetchInProgress = true;
    Future(() async {
      // Fetch puzzles until the pool is full or we fail.
      int attempts = 0;
      while (_pool.length < _kMaxPoolSize && attempts < 30) {
        attempts++;
        try {
          final puzzle = await _api.fetchNextPuzzle();
          _addToPool(puzzle);
        } catch (_) {
          // Network error — stop trying for now.
          break;
        }
        // Yield to the event loop between requests to avoid blocking.
        await Future.delayed(const Duration(milliseconds: 200));
      }
      _fetchInProgress = false;
    });
  }

  // ── TacticsTaskProvider ──────────────────────────────────────────────────────

  @override
  Future<TacticsTask> fetchNextTask() async {
    await _ensureSeedLoaded();

    // Kick off a background fetch if the pool is running low.
    if (_pool.length < _kRefillThreshold) {
      _triggerBackgroundFetch();
    }

    // Determine target rating.
    final userRating = await TacticsStorage.loadRating(mode: 'classic');
    final ratingOffset = await TacticsStorage.loadRatingOffset();
    final targetRating = userRating + ratingOffset;

    // If the pool is completely empty, wait for a synchronous fetch.
    if (_pool.isEmpty) {
      try {
        final puzzle = await _api.fetchNextPuzzle();
        _addToPool(puzzle);
      } catch (e) {
        throw Exception(
            '[RatingAwareClassicProvider] Pool is empty and network fetch failed: $e');
      }
    }

    // ── Root Cause 1, 2 & 3 Fix: Selection with strict rating window + randomization + persistent seen filtering ──
    const int maxAcceptableDelta = 250;

    // 1. Filter pool for puzzles not yet seen in recent sessions.
    final unseenPool =
        _pool.where((e) => !_seenIds.contains(e.puzzle.id)).toList();

    // 2. Try to find unseen candidates within maxAcceptableDelta of targetRating.
    List<_PoolEntry> eligible = unseenPool.where((e) {
      return (e.puzzle.rating - targetRating).abs() <= maxAcceptableDelta;
    }).toList();

    // 3. If no unseen puzzle matches the rating window, allow recycling seen puzzles WITHIN maxAcceptableDelta.
    if (eligible.isEmpty) {
      eligible = _pool.where((e) {
        return (e.puzzle.rating - targetRating).abs() <= maxAcceptableDelta;
      }).toList();
    }

    // 4. If pool has no puzzle within maxAcceptableDelta of target, find closest available puzzles in pool.
    if (eligible.isEmpty && _pool.isNotEmpty) {
      int minDelta = 0x7fffffff;
      for (final entry in _pool) {
        final delta = (entry.puzzle.rating - targetRating).abs();
        if (delta < minDelta) minDelta = delta;
      }
      eligible = _pool.where((e) {
        return (e.puzzle.rating - targetRating).abs() <= minDelta + 150;
      }).toList();
    }

    final source = eligible.isNotEmpty ? eligible : _pool;

    // Sort candidates by closeness to target rating.
    source.sort((a, b) {
      final deltaA = (a.puzzle.rating - targetRating).abs();
      final deltaB = (b.puzzle.rating - targetRating).abs();
      return deltaA.compareTo(deltaB);
    });

    // Pick randomly among the top 5 closest candidates to guarantee rating accuracy + variety.
    final topCandidates = source.take(5).toList()..shuffle();
    final best = topCandidates.first;

    final actualDelta = (best.puzzle.rating - targetRating).abs();

    _pool.remove(best);
    _seenIds.add(best.puzzle.id);
    if (_seenIds.length > 50) {
      _seenIds.removeRange(0, _seenIds.length - 50);
    }
    TacticsStorage.saveRecentPuzzleIds(_seenIds, mode: 'classic');

    debugPrint('[RatingAwareClassicProvider] Serving puzzle ${best.puzzle.id} '
        '(rating ${best.puzzle.rating}, target $targetRating, '
        'delta $actualDelta, pool size ${_pool.length})');

    return _mapToTask(best.puzzle);
  }

  @override
  Future<TacticsTask> fetchTaskById(String id) async {
    await _ensureSeedLoaded();
    // Check pool first.
    final cached = _pool.where((e) => e.puzzle.id == id).firstOrNull;
    if (cached != null) return _mapToTask(cached.puzzle);
    // Fetch from API.
    final puzzle = await _api.fetchPuzzleById(id);
    return _mapToTask(puzzle);
  }

  TacticsTask _mapToTask(LichessPuzzle puzzle) {
    return TacticsTask(
      id: puzzle.id,
      fen: puzzle.fen,
      mode: TacticsMode.classic,
      expectedMoves: puzzle.solution,
      difficulty: puzzle.rating,
      displayRating: puzzle.rating,
      searchRating: puzzle.rating,
      antiTacticsType: null,
      explanation: null,
      lastMove: puzzle.lastMove,
      themes: puzzle.themes,
    );
  }
}

/// Lightweight pool entry wrapper.
class _PoolEntry {
  final LichessPuzzle puzzle;
  _PoolEntry(this.puzzle);
}
