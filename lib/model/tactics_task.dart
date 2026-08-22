enum TacticsMode {
  classic,
  antiTactics,
  antiTacticsV2,
  blindfold,
  puzzleRush,
  tactics2
}

enum AntiTacticsType { winningTacticExists, noWinningTactic }

enum TacticsAction { declareNoTactic }

class TacticsTask {
  final String id;
  final String fen;
  final TacticsMode mode;
  final AntiTacticsType? antiTacticsType;
  final List<String> expectedMoves;
  final int difficulty;
  final String? explanation;
  final String? explanationShort;
  final List<String> tags;
  final String? phase;
  final String? lastMove;
  final int? version;

  // Additional specification fields
  final String? colorToMove;
  final int? searchRating;
  final int? displayRating;
  final String? type;
  final List<String> themes;

  const TacticsTask({
    required this.id,
    required this.fen,
    required this.mode,
    required this.expectedMoves,
    required this.difficulty,
    this.antiTacticsType,
    this.explanation,
    this.explanationShort,
    this.tags = const [],
    this.phase,
    this.lastMove,
    this.version,
    this.colorToMove,
    this.searchRating,
    this.displayRating,
    this.type,
    this.themes = const [],
  });

  String get effectiveColorToMove => colorToMove ?? _extractColorToMove(fen);

  int get effectiveSearchRating => searchRating ?? difficulty;

  int get effectiveDisplayRating => displayRating ?? difficulty;

  String get effectiveType =>
      type ??
      ((mode == TacticsMode.antiTactics || mode == TacticsMode.antiTacticsV2)
          ? 'antitactic'
          : 'tactic');

  static String _extractColorToMove(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return parts[1] == 'w' ? 'white' : 'black';
    }
    return 'white';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fen': fen,
      'color_to_move': effectiveColorToMove,
      'type': effectiveType,
      'search_rating': effectiveSearchRating,
      'display_rating': effectiveDisplayRating,
      'themes': themes.isNotEmpty ? themes : tags,
      'mode': mode.name,
      'antiTacticsType': antiTacticsType?.name,
      'expectedMoves': expectedMoves,
      'difficulty': difficulty,
      'explanation': explanation,
      'explanationShort': explanationShort,
      'tags': tags,
      'phase': phase,
      'lastMove': lastMove,
      'version': version,
    };
  }

  factory TacticsTask.fromJson(Map<String, dynamic> json) {
    TacticsMode mode = TacticsMode.classic;
    if (json['mode'] == 'antiTactics') mode = TacticsMode.antiTactics;
    if (json['mode'] == 'antiTacticsV2') mode = TacticsMode.antiTacticsV2;
    if (json['mode'] == 'blindfold') mode = TacticsMode.blindfold;
    if (json['mode'] == 'puzzleRush') mode = TacticsMode.puzzleRush;

    AntiTacticsType? type;
    if (json['antiTacticsType'] == 'winningTacticExists') {
      type = AntiTacticsType.winningTacticExists;
    } else if (json['antiTacticsType'] == 'noWinningTactic') {
      type = AntiTacticsType.noWinningTactic;
    }

    final diff = json['difficulty'] as int? ?? 1000;
    final sRating = json['search_rating'] as int? ?? diff;
    final dRating = json['display_rating'] as int? ?? diff;
    final taskType = json['type'] as String? ??
        ((mode == TacticsMode.antiTactics || mode == TacticsMode.antiTacticsV2)
            ? 'antitactic'
            : 'tactic');

    return TacticsTask(
      id: json['id'] as String,
      fen: json['fen'] as String,
      mode: mode,
      expectedMoves: (json['expectedMoves'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      difficulty: diff,
      searchRating: sRating,
      displayRating: dRating,
      type: taskType,
      colorToMove: json['color_to_move'] as String?,
      antiTacticsType: type,
      explanation: json['explanation'] as String?,
      explanationShort: json['explanationShort'] as String?,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              [],
      themes: (json['themes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      phase: json['phase'] as String?,
      lastMove: json['lastMove'] as String?,
      version: json['version'] as int?,
    );
  }
}
