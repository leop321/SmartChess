import '../../model/puzzle.dart';
import 'lichess_puzzle_client.dart';
import 'puzzle_repository.dart';

/// Lichess-Implementierung des [PuzzleRepository].
class LichessPuzzleRepository implements PuzzleRepository {
  final LichessPuzzleClient _client;

  LichessPuzzleRepository({LichessPuzzleClient? client})
      : _client = client ?? LichessPuzzleClient();

  // Übergangslösung – fester ID-Pool statt Daily-Endpunkt. Sollte durch eine
  // dynamische/größere Quelle ersetzt werden, sobald Rating-/Themenfilterung benötigt wird (siehe bestehendes TODO).
  static const List<String> _puzzleIds = [
    '0009B', '000aY', '000hf', 'b82yB', '01vf9', '01z0l', '020Bj', '022Lj', '023un', '00008'
  ];
  int _currentIndex = 0;

  @override
  Future<Puzzle> getNextPuzzle({
    int? minRating,
    int? maxRating,
    List<String>? themes,
  }) async {
    // TODO: Rating-Filter erfordert lokalen Puzzle-Pool, da die API keine Filterung nach Rating erlaubt
    final id = _puzzleIds[_currentIndex];
    _currentIndex = (_currentIndex + 1) % _puzzleIds.length;
    return _client.fetchPuzzleById(id);
  }
}
