import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import '../model/lichess_puzzle.dart';
import '../model/tactics_task.dart';

/// A simple, robust 3-puzzle queue manager for offline tactics.
///
/// Ensures:
///  1. Exactly 3 puzzles are pre-buffered (current + 2 upcoming).
///  2. Queue & progress are persisted across app restarts & lifecycle pauses.
///  3. Played IDs are tracked globally across sessions so puzzles never repeat until the pool recycles.
///  4. Refills queue automatically to 3 when a puzzle is completed.
class SimpleTacticsQueue {
  final List<TacticsTask> _queue = [];
  final Set<String> _playedIds = {};
  bool _initialized = false;

  List<TacticsTask> get queue => List.unmodifiable(_queue);

  /// Returns the current active puzzle (queue[0]).
  TacticsTask? get current => _queue.isNotEmpty ? _queue.first : null;

  String _getQueueKey(TacticsMode mode) => 'simple_tactics_queue_${mode.name}';
  String _getPlayedKey(TacticsMode mode) =>
      'simple_tactics_played_ids_${mode.name}';

  /// Restores queue and played IDs from SharedPreferences. If empty or insufficient,
  /// fills the queue to 3 tasks from the local dataset.
  Future<void> restore(TacticsMode mode) async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load played IDs
      final savedPlayed = prefs.getStringList(_getPlayedKey(mode)) ?? [];
      _playedIds.addAll(savedPlayed);

      // Load saved queue
      final rawQueue = prefs.getStringList(_getQueueKey(mode)) ?? [];
      _queue.clear();
      for (final jsonStr in rawQueue) {
        try {
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          final task = TacticsTask.fromJson(map);
          _queue.add(task);
        } catch (e) {
          debugPrint('[SimpleTacticsQueue] Restore task parse error: $e');
        }
      }
    } catch (e) {
      debugPrint('[SimpleTacticsQueue] Restore error: $e');
    }

    // Ensure queue has 3 tasks
    await _refillQueue(mode);
    await persist(mode);
  }

  /// Advances to the next puzzle in the queue, adding the finished puzzle to played IDs
  /// and refilling the queue to 3 items.
  Future<TacticsTask?> advance(TacticsMode mode) async {
    if (_queue.isNotEmpty) {
      final completed = _queue.removeAt(0);
      _playedIds.add(completed.id);
    }

    await _refillQueue(mode);
    await persist(mode);
    return current;
  }

  /// Persists current 3-puzzle queue and played IDs to SharedPreferences.
  Future<void> persist(TacticsMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serializedQueue =
          _queue.map((t) => jsonEncode(t.toJson())).toList();
      await prefs.setStringList(_getQueueKey(mode), serializedQueue);

      // Cap played IDs at 200 to keep preferences lightweight while preventing repeats
      final playedList = _playedIds.toList();
      final trimmedPlayed = playedList.length > 200
          ? playedList.sublist(playedList.length - 200)
          : playedList;
      await prefs.setStringList(_getPlayedKey(mode), trimmedPlayed);
    } catch (e) {
      debugPrint('[SimpleTacticsQueue] Persist error: $e');
    }
  }

  /// Fills `_queue` up to 3 tasks using local dataset assets.
  Future<void> _refillQueue(TacticsMode mode) async {
    if (_queue.length >= 3) return;

    final String assetPath =
        (mode == TacticsMode.antiTactics || mode == TacticsMode.antiTacticsV2)
            ? 'assets/data/anti_tactics_tasks.json'
            : 'assets/data/lichess_puzzles.json';

    try {
      final jsonString = await rootBundle.loadString(assetPath);
      final List<dynamic> jsonList = jsonDecode(jsonString);

      final List<TacticsTask> pool = [];
      for (final entry in jsonList) {
        try {
          if (mode == TacticsMode.antiTactics ||
              mode == TacticsMode.antiTacticsV2) {
            pool.add(TacticsTask.fromJson(Map<String, dynamic>.from(entry)));
          } else {
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
            pool.add(TacticsTask(
              id: puzzle.id,
              fen: puzzle.fen,
              mode: TacticsMode.classic,
              expectedMoves: puzzle.solution,
              difficulty: puzzle.rating,
              displayRating: puzzle.rating,
              searchRating: puzzle.rating,
              lastMove: puzzle.lastMove,
              themes: puzzle.themes,
            ));
          }
        } catch (_) {}
      }

      final existingQueueIds = _queue.map((t) => t.id).toSet();

      // Candidates not in queue AND not in playedIds
      List<TacticsTask> candidates = pool
          .where((t) =>
              !existingQueueIds.contains(t.id) && !_playedIds.contains(t.id))
          .toList();

      // If pool is exhausted relative to playedIds, recycle older played IDs
      if (candidates.isEmpty && pool.isNotEmpty) {
        if (_playedIds.length > 10) {
          _playedIds
              .removeAll(_playedIds.take(_playedIds.length - 10).toList());
        } else {
          _playedIds.clear();
        }
        candidates = pool
            .where((t) =>
                !existingQueueIds.contains(t.id) && !_playedIds.contains(t.id))
            .toList();
        if (candidates.isEmpty) {
          candidates =
              pool.where((t) => !existingQueueIds.contains(t.id)).toList();
        }
      }

      final random = Random();
      while (_queue.length < 3 && candidates.isNotEmpty) {
        final selectedIndex = random.nextInt(candidates.length);
        final selectedTask = candidates.removeAt(selectedIndex);
        _queue.add(selectedTask);
      }
    } catch (e) {
      debugPrint('[SimpleTacticsQueue] Refill queue error: $e');
    }
  }
}
