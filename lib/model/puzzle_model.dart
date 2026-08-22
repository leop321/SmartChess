class PuzzleModel {
  final String id;
  final int rating;
  final String fen;
  final List<String> moves;
  final List<String> themes;

  PuzzleModel({
    required this.id,
    required this.rating,
    required this.fen,
    required this.moves,
    required this.themes,
  });

  factory PuzzleModel.fromJson(Map<String, dynamic> json) {
    final game = json['game'];
    final puzzle = json['puzzle'];

    List<String> parsedMoves = [];
    if (puzzle != null && puzzle['solution'] != null) {
      parsedMoves = List<String>.from(puzzle['solution']);
    }

    List<String> parsedThemes = [];
    if (puzzle != null && puzzle['themes'] != null) {
      parsedThemes = List<String>.from(puzzle['themes']);
    }

    // Lichess Daily Puzzle API returns FEN at puzzle.fen
    // (not at root or game level). Fallback to empty string if missing.

    return PuzzleModel(
      id: puzzle != null
          ? puzzle['id']?.toString() ?? ''
          : json['id']?.toString() ?? '',
      rating: puzzle != null
          ? (puzzle['rating'] as int?) ?? 1500
          : (json['rating'] as int?) ?? 1500,
      fen: puzzle?['fen'] ?? json['fen'] ?? game?['fen'] ?? '',
      moves: parsedMoves,
      themes: parsedThemes,
    );
  }
}

class PuzzleStreakData {
  final double elo;
  final bool win;

  PuzzleStreakData(this.elo, this.win);
}
