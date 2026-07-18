class ChessPuzzle {
  final String id;
  final String startingFen;
  
  /// The correct sequence of moves for the puzzle.
  /// Alternates: Player move 1, Opponent reply 1, Player move 2, Opponent reply 2...
  /// Example: ['d4', 'd5', 'c4'] or ['d2d4', 'd7d5', 'c2c4']
  final List<String> solutionMoves;
  
  final String description;
  final String theme;

  const ChessPuzzle({
    required this.id,
    required this.startingFen,
    required this.solutionMoves,
    this.description = '',
    this.theme = '',
  });

  /// Load from a JSON Map.
  factory ChessPuzzle.fromJson(Map<String, dynamic> json) {
    return ChessPuzzle(
      id: json['id'] as String,
      startingFen: json['startingFen'] as String,
      solutionMoves: List<String>.from(json['solutionMoves'] as List),
      description: json['description'] as String? ?? '',
      theme: json['theme'] as String? ?? '',
    );
  }

  /// Convert to a JSON Map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startingFen': startingFen,
      'description': description,
      'theme': theme,
      'solutionMoves': solutionMoves,
    };
  }
}
