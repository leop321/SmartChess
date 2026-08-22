import 'package:chess/chess.dart' as chess;

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

  /// Erzeugt ein Puzzle aus dem offiziellen Lichess API JSON Format (z.B. api/puzzle/daily).
  ///
  /// **JSON-Struktur der Lichess API:**
  /// - `game.pgn`: Die vollständige PGN der Partie bis einschließlich des Gegnerzugs.
  /// - `puzzle.id`: Eindeutige ID des Puzzles.
  /// - `puzzle.rating`: Das Rating des Puzzles.
  /// - `puzzle.themes`: Array von Themen (Strings).
  /// - `puzzle.fen`: Die FEN **NACH** dem Gegnerzug (also die Spieler-Startstellung).
  /// - `puzzle.lastMove`: Der Zug des Gegners im UCI-Format.
  /// - `puzzle.solution`: Array der Lösungszüge des Spielers im UCI-Format (Gegnerzug fehlt!).
  ///
  /// Da unsere App-Architektur zwingend verlangt, dass der ERSTE Zug in [solutionMoves]
  /// der Gegnerzug ist und [fen] die Stellung Davor sein muss, nutzen wir das `chess`
  /// Paket, um die FEN durch Zurücknehmen von `lastMove` in der PGN zu berechnen.
  factory Puzzle.fromLichessJson(Map<String, dynamic> json) {
    final puzzleMap = json['puzzle'];
    final gameMap = json['game'];

    if (puzzleMap == null) {
      throw const FormatException('Lichess-JSON fehlt Pflichtfeld "puzzle"');
    }
    if (gameMap == null) {
      throw const FormatException('Lichess-JSON fehlt Pflichtfeld "game"');
    }

    final id = puzzleMap['id']?.toString();
    if (id == null)
      throw const FormatException('Lichess-JSON fehlt Pflichtfeld "puzzle.id"');

    final rating = puzzleMap['rating'] as int?;
    if (rating == null)
      throw const FormatException(
          'Lichess-JSON fehlt Pflichtfeld "puzzle.rating"');

    final pgn = gameMap['pgn']?.toString();
    if (pgn == null)
      throw const FormatException(
          'Lichess-JSON fehlt Pflichtfeld "game.pgn" zur Berechnung der Start-FEN');

    final lastMove = puzzleMap['lastMove']?.toString();
    if (lastMove == null)
      throw const FormatException(
          'Lichess-JSON fehlt Pflichtfeld "puzzle.lastMove"');

    final solutionRaw = puzzleMap['solution'] as List<dynamic>?;
    if (solutionRaw == null)
      throw const FormatException(
          'Lichess-JSON fehlt Pflichtfeld "puzzle.solution"');

    final solution = solutionRaw.map((e) => e.toString()).toList();

    final themesRaw = puzzleMap['themes'] as List<dynamic>?;
    final themes = themesRaw?.map((e) => e.toString()).toList() ?? [];

    // FEN VOR dem Gegnerzug berechnen
    // 1. PGN laden (enthält den Gegnerzug als letzten Zug)
    final chessEngine = chess.Chess();
    final loaded = chessEngine.load_pgn(pgn);
    if (!loaded) {
      throw FormatException(
          'Konnte PGN in Lichess-JSON nicht parsen (ID: $id)');
    }

    // 2. Den Gegnerzug zurücknehmen, um die FEN DAVOR zu erhalten
    chessEngine.undo_move();
    final fenBeforeLastMove = chessEngine.generate_fen();

    // 3. Lösung zusammensetzen (Gegnerzug + Spielerzüge)
    final fullSolution = [lastMove, ...solution];

    return Puzzle(
      id: id,
      fen: fenBeforeLastMove,
      solutionMoves: fullSolution,
      rating: rating,
      themes: themes,
      sourceUrl: 'https://lichess.org/training/$id',
    );
  }
}
