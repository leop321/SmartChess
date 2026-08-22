/// Repräsentiert eine Schach-Taktikaufgabe (Puzzle).
///
/// **Wichtige Konvention (Lichess-Format):**
/// In Lichess-Puzzle-Daten (und in diesem Modell) stellt der *erste* Zug in der
/// [solutionMoves]-Liste **immer den Zug des Gegners** dar. Dieser Zug überführt die
/// Startstellung ([fen]) in die eigentliche Taktikposition, ab der der Spieler lösen muss.
/// Der Spieler muss also immer auf den ersten Zug aus [solutionMoves] antworten.
class Puzzle {
  final String id;

  /// Die Startstellung vor dem ersten Zug der Lösung (oft der Zug des Gegners).
  final String fen;

  /// Die Lösungszugfolge im UCI-Format (z.B. "e2e4", "e7e8q").
  /// Der erste Zug ist konventionsgemäß der Zug des Gegners.
  final List<String> solutionMoves;

  final int rating;
  final List<String> themes;
  final String? sourceUrl;

  const Puzzle({
    required this.id,
    required this.fen,
    required this.solutionMoves,
    required this.rating,
    required this.themes,
    this.sourceUrl,
  });

  factory Puzzle.fromLichessJson(Map<String, dynamic> json) {
    throw UnimplementedError('Lichess-Adapter folgt in Schritt 8');
  }
}
