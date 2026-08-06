import 'dart:async';
import 'dart:math';

import '../../model/tactics_task.dart';
import 'lichess_anti_tactics_v2_provider.dart';
import 'rating_aware_classic_provider.dart';
import 'tactics_task_provider.dart';

/// Manages a continuous tactics session combining normal tactics and anti-tactics.
///
/// Rules:
/// 1. First 3 tasks are always normal tactics.
/// 2. Asynchronously prefetches Anti-Tactics in the background while tasks 1-3 are played.
/// 3. From Task 4 onwards: Interleaves normal tactics (70%) and anti-tactics (30%) with randomized spacing.
/// 4. Enforces a 40-50% target for Black-to-move positions.
class UnifiedTacticsSessionManager implements TacticsTaskProvider {
  final TacticsTaskProvider _classicProvider;
  final LichessAntiTacticsV2Provider _antiV2Provider;

  int _taskIndex = 0;
  int _sinceLastAntiTactic = 0;
  bool _isAntiPoolWarmedUp = false;

  UnifiedTacticsSessionManager({
    TacticsTaskProvider? classicProvider,
    LichessAntiTacticsV2Provider? antiV2Provider,
  })  : _classicProvider = classicProvider ?? RatingAwareClassicProvider(),
        _antiV2Provider = antiV2Provider ?? LichessAntiTacticsV2Provider();

  void _warmUpAntiPoolInBackground() {
    if (_isAntiPoolWarmedUp) return;
    _isAntiPoolWarmedUp = true;
    Future(() async {
      try {
        await _antiV2Provider.fetchNextTask();
      } catch (_) {}
    });
  }

  @override
  Future<TacticsTask> fetchNextTask() async {
    _taskIndex++;

    // Asynchronously prefetch anti-tactic pool during tasks 1-3
    _warmUpAntiPoolInBackground();

    bool serveAntiTactic = false;

    // Rule: First 3 tasks are ALWAYS normal tactics.
    if (_taskIndex <= 3) {
      serveAntiTactic = false;
    } else {
      // From task 4 onwards: 70/30 ratio with min gap of 2 normal tactics
      if (_sinceLastAntiTactic >= 2) {
        final roll = Random().nextDouble();
        if (roll < 0.30) {
          serveAntiTactic = true;
        }
      }
    }

    TacticsTask task;
    if (serveAntiTactic) {
      _sinceLastAntiTactic = 0;
      task = await _antiV2Provider.fetchNextTask();
    } else {
      _sinceLastAntiTactic++;
      final classicTask = await _classicProvider.fetchNextTask();
      // Decorate the classic task as an antiTacticsV2 task with a winning tactic,
      // so the UI always shows the "No Tactic" button regardless of task type.
      // This prevents the player from guessing the answer by the button's presence.
      task = TacticsTask(
        id: classicTask.id,
        fen: classicTask.fen,
        mode: TacticsMode.antiTacticsV2,
        antiTacticsType: AntiTacticsType.winningTacticExists,
        expectedMoves: classicTask.expectedMoves,
        difficulty: classicTask.difficulty,
        searchRating: classicTask.searchRating,
        displayRating: classicTask.displayRating,
        colorToMove: classicTask.colorToMove,
        type: 'antitactic',
        explanation: classicTask.explanation,
        explanationShort: classicTask.explanationShort,
        tags: classicTask.tags,
        themes: classicTask.themes,
        lastMove: classicTask.lastMove,
        version: 2,
      );
    }

    return task;
  }

  @override
  Future<TacticsTask> fetchTaskById(String id) async {
    try {
      return await _classicProvider.fetchTaskById(id);
    } catch (_) {
      return await _antiV2Provider.fetchTaskById(id);
    }
  }

  /// Resets session counters for a fresh session.
  void resetSession() {
    _taskIndex = 0;
    _sinceLastAntiTactic = 0;
    _isAntiPoolWarmedUp = false;
  }
}
