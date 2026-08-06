import '../../model/lichess_puzzle.dart';
import '../../model/tactics_task.dart';
import '../lichess_puzzle_service.dart';
import 'tactics_task_provider.dart';

class LichessClassicProvider implements TacticsTaskProvider {
  final LichessPuzzleService api;

  LichessClassicProvider({LichessPuzzleService? api})
      : api = api ?? LichessPuzzleService();

  TacticsTask _mapLichessToTask(LichessPuzzle puzzle) {
    return TacticsTask(
      id: puzzle.id,
      fen: puzzle.fen,
      mode: TacticsMode.classic,
      expectedMoves: puzzle.solution,
      difficulty: puzzle.rating,
      antiTacticsType: null,
      explanation: null,
      lastMove: puzzle.lastMove,
    );
  }

  @override
  Future<TacticsTask> fetchNextTask() async {
    final puzzle = await api.fetchNextPuzzle();
    return _mapLichessToTask(puzzle);
  }

  @override
  Future<TacticsTask> fetchTaskById(String id) async {
    final puzzle = await api.fetchPuzzleById(id);
    return _mapLichessToTask(puzzle);
  }
}
