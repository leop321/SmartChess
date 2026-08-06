import 'dart:math';

import '../../model/tactics_task.dart';
import 'tactics_task_provider.dart';

class LocalAntiTacticsProvider implements TacticsTaskProvider {
  // A few hardcoded mock puzzles for Anti-Tactics
  static const List<TacticsTask> _mocks = [
    // 1. Position with a clear tactic (Winning)
    TacticsTask(
      id: 'mock_anti_1',
      // An easy back-rank mate: White to move, Rb8#
      fen: '6k1/5ppp/8/8/8/8/8/1R4K1 w - - 0 1',
      mode: TacticsMode.antiTactics,
      antiTacticsType: AntiTacticsType.winningTacticExists,
      expectedMoves: ['b1b8'],
      difficulty: 800,
      explanation: 'Es gibt ein klassisches Grundreihenmatt (Turm b1 nach b8).',
    ),
    // 2. Position with NO winning tactic (Equal Endgame)
    TacticsTask(
      id: 'mock_anti_2',
      // Completely equal endgame, no forcing sequence
      fen: '8/p4pkp/1p4p1/8/8/1P4P1/P4PKP/8 w - - 0 1',
      mode: TacticsMode.antiTactics,
      antiTacticsType: AntiTacticsType.noWinningTactic,
      expectedMoves: [], // No sequence
      difficulty: 1200,
      explanation:
          'Die Stellung ist ein absolut ausgeglichenes Bauernendspiel. Jeder Taktik-Versuch verliert wahrscheinlich.',
    ),
    // 3. Another winning tactic (Queen Fork)
    TacticsTask(
      id: 'mock_anti_3',
      // Queen fork: Qe4-a8 winning the unprotected rook on a8
      fen: 'r3k3/8/8/8/4Q3/8/8/4K3 w - - 0 1',
      mode: TacticsMode.antiTactics,
      antiTacticsType: AntiTacticsType.winningTacticExists,
      expectedMoves: ['e4a8'],
      difficulty: 1000,
      explanation:
          'Die Dame greift den ungedeckten Turm auf a8 an und gewinnt ihn.',
    ),
    // 4. Position with NO winning tactic (Symmetrical Opening)
    TacticsTask(
      id: 'mock_anti_4',
      // Symmetrical position after 1.e4 e5, no forcing sequence
      fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
      mode: TacticsMode.antiTactics,
      antiTacticsType: AntiTacticsType.noWinningTactic,
      expectedMoves: [],
      difficulty: 900,
      explanation:
          'Eine symmetrische Eröffnung (1.e4 e5). Es gibt keine direkte taktische Lösung.',
    ),
  ];

  @override
  Future<TacticsTask> fetchNextTask() async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 300));
    final random = Random().nextInt(3); // Use all 3 mocks
    return _mocks[random];
  }

  @override
  Future<TacticsTask> fetchTaskById(String id) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return _mocks.firstWhere(
      (t) => t.id == id,
      orElse: () => _mocks[0],
    );
  }
}
