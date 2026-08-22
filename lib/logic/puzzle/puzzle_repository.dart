import '../../model/puzzle.dart';

/// Abstrakte Schnittstelle für einen Puzzle-Anbieter.
abstract class PuzzleRepository {
  /// Lädt das nächste Puzzle basierend auf optionalen Filterkriterien.
  Future<Puzzle> getNextPuzzle({
    int? minRating,
    int? maxRating,
    List<String>? themes,
  });
}
