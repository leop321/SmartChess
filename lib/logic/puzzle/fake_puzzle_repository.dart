import '../../model/puzzle.dart';
import 'puzzle_repository.dart';

/// Eine Fake-Implementierung des [PuzzleRepository] für Tests und lokale Entwicklung.
/// Enthält fest codierte, verifizierte Puzzles und rotiert durch diese.
class FakePuzzleRepository implements PuzzleRepository {
  int _currentIndex = 0;

  // 3 fest codierte Puzzles.
  // Wichtig: Der erste Zug in solutionMoves ist der Zug des Gegners!
  static const List<Puzzle> _puzzles = [
    // Puzzle 1: Aus dem alten Lichess-Datensatz ("00008")
    Puzzle(
      id: 'fake-1',
      fen:
          'r6k/pp2r2p/4Rp1Q/3p4/8/1N1P2R1/Pbq2PPP/7K b - - 0 24', // Schwarz am Zug (Gegner)
      solutionMoves: [
        'c2b1',
        'b3c1',
        'b1c1',
        'h6c1',
        'b2g3'
      ], // Schwarz spielt c2b1, Weiß antwortet mit b3c1 usw.
      rating: 1500,
      themes: ['mate', 'mateIn2', 'short'],
    ),
    // Puzzle 2: Einfaches Matt in 1 (Schäfermatt-Setup)
    Puzzle(
      id: 'fake-2',
      fen:
          'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5Q2/PPPP1PPP/RNB1K1NR b KQkq - 3 3', // Schwarz am Zug (Gegner)
      solutionMoves: [
        'c6d4',
        'f3f7'
      ], // Schwarz spielt c6-d4, Weiß mattiert mit f3-f7#
      rating: 800,
      themes: ['mate', 'mateIn1'],
    ),
    // Puzzle 3: Grundreihenmatt
    Puzzle(
      id: 'fake-3',
      fen: '6k1/5ppp/8/8/8/8/5PPP/R5K1 b - - 0 1', // Schwarz am Zug (Gegner)
      solutionMoves: [
        'h7h6',
        'a1a8'
      ], // Schwarz spielt h7-h6 (verhindert das Matt auf h8, aber nicht auf a8), Weiß mattiert mit a1-a8#
      rating: 1000,
      themes: ['mate', 'mateIn1', 'backRankMate'],
    ),
  ];

  @override
  Future<Puzzle> getNextPuzzle({
    int? minRating,
    int? maxRating,
    List<String>? themes,
  }) async {
    // Simuliere eine kleine Netzwerkverzögerung
    await Future.delayed(const Duration(milliseconds: 150));

    final puzzle = _puzzles[_currentIndex];

    // Rotiere zum nächsten Puzzle
    _currentIndex = (_currentIndex + 1) % _puzzles.length;

    return puzzle;
  }
}
