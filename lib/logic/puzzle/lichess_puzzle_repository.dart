import '../../model/puzzle.dart';
import 'lichess_puzzle_client.dart';
import 'puzzle_repository.dart';

/// Lichess-Implementierung des [PuzzleRepository].
class LichessPuzzleRepository implements PuzzleRepository {
  final LichessPuzzleClient _client;

  LichessPuzzleRepository({LichessPuzzleClient? client})
      : _client = client ?? LichessPuzzleClient();

  @override
  Future<Puzzle> getNextPuzzle({
    int? minRating,
    int? maxRating,
    List<String>? themes,
  }) async {
    // TODO: Rating-Filter erfordert lokalen Puzzle-Pool, da die API keine Filterung nach Rating erlaubt
    // Für diesen MVP holen wir stattdessen das tagesaktuelle Puzzle
    return _client.fetchDailyPuzzle();
  }
}
