/// Normalized data models for the Analysis feature.
/// Adapted from MoveLab's main.dart (SavedMatch, PlayerStyleProfile, MoveAnalysis).
/// Firebase / cloud sync intentionally removed — local only.
library game_analysis_models;

// ─── Source Platform ──────────────────────────────────────────────────────────

enum GamePlatform { lichess, chessCom, local }

extension GamePlatformX on GamePlatform {
  String get displayName {
    switch (this) {
      case GamePlatform.lichess:
        return 'Lichess';
      case GamePlatform.chessCom:
        return 'Chess.com';
      case GamePlatform.local:
        return 'Local';
    }
  }
}

// ─── Game Entry (normalised across platforms) ─────────────────────────────────

class GameEntry {
  final GamePlatform platform;
  final String white;
  final String black;
  final String whiteTitle;
  final String blackTitle;
  final int whiteRating;
  final int blackRating;

  /// 'white' | 'black' | 'draw'
  final String winner;

  /// e.g. 'blitz', 'rapid', 'bullet', 'classical'
  final String speed;

  /// Full PGN text (may be empty for Lichess move-list games)
  final String pgn;

  /// Space-separated move list in UCI/SAN (used for style analysis)
  final String moves;

  final double? whiteAccuracy;
  final double? blackAccuracy;

  /// ISO-8601 date string or empty
  final String date;

  const GameEntry({
    required this.platform,
    required this.white,
    required this.black,
    this.whiteTitle = '',
    this.blackTitle = '',
    this.whiteRating = 0,
    this.blackRating = 0,
    required this.winner,
    required this.speed,
    this.pgn = '',
    this.moves = '',
    this.whiteAccuracy,
    this.blackAccuracy,
    this.date = '',
  });

  Map<String, dynamic> toJson() => {
        'platform': platform.name,
        'white': white,
        'black': black,
        'whiteTitle': whiteTitle,
        'blackTitle': blackTitle,
        'whiteRating': whiteRating,
        'blackRating': blackRating,
        'winner': winner,
        'speed': speed,
        'pgn': pgn,
        'moves': moves,
        'whiteAccuracy': whiteAccuracy,
        'blackAccuracy': blackAccuracy,
        'date': date,
      };

  factory GameEntry.fromJson(Map<String, dynamic> json) {
    return GameEntry(
      platform: GamePlatform.values.firstWhere(
        (e) => e.name == (json['platform'] ?? 'local'),
        orElse: () => GamePlatform.local,
      ),
      white: json['white'] ?? '',
      black: json['black'] ?? '',
      whiteTitle: json['whiteTitle'] ?? '',
      blackTitle: json['blackTitle'] ?? '',
      whiteRating: json['whiteRating'] ?? 0,
      blackRating: json['blackRating'] ?? 0,
      winner: json['winner'] ?? 'draw',
      speed: json['speed'] ?? '',
      pgn: json['pgn'] ?? '',
      moves: json['moves'] ?? '',
      whiteAccuracy: (json['whiteAccuracy'] as num?)?.toDouble(),
      blackAccuracy: (json['blackAccuracy'] as num?)?.toDouble(),
      date: json['date'] ?? '',
    );
  }
}

// ─── Player Profile ────────────────────────────────────────────────────────────

class PlayerProfile {
  final String username;
  final String title;
  final int? rapid;
  final int? blitz;
  final int? bullet;

  const PlayerProfile({
    required this.username,
    this.title = '',
    this.rapid,
    this.blitz,
    this.bullet,
  });

  int get bestRating {
    final vals = [rapid ?? 0, blitz ?? 0, bullet ?? 0];
    return vals.reduce((a, b) => a > b ? a : b);
  }
}

// ─── Player Style Profile ──────────────────────────────────────────────────────

/// Adapted from MoveLab's PlayerStyleProfile (line 1243).
class PlayerStyleProfile {
  final int aggressive;
  final int defensive;
  final int tactical;
  final int positional;
  final int opening;
  final int risk;
  final String mainStyle;
  final String mainIcon;
  final List<String> subStyles;

  const PlayerStyleProfile({
    required this.aggressive,
    required this.defensive,
    required this.tactical,
    required this.positional,
    required this.opening,
    required this.risk,
    required this.mainStyle,
    required this.mainIcon,
    required this.subStyles,
  });

  static PlayerStyleProfile neutral() => const PlayerStyleProfile(
        aggressive: 50,
        defensive: 50,
        tactical: 50,
        positional: 50,
        opening: 50,
        risk: 50,
        mainStyle: 'Balanced',
        mainIcon: '⚖️',
        subStyles: [],
      );
}

// ─── Move Analysis ─────────────────────────────────────────────────────────────

/// Adapted from MoveLab's MoveAnalysis (line 841).
class MoveAnalysis {
  final double bestEval;
  final double playedEval;
  final double accuracy;
  final String qualityLabel;
  final bool isBrilliant;
  final bool isGreat;

  const MoveAnalysis({
    required this.bestEval,
    required this.playedEval,
    required this.accuracy,
    required this.qualityLabel,
    required this.isBrilliant,
    required this.isGreat,
  });
}

// ─── Saved Analysis Game (local library) ──────────────────────────────────────

class SavedAnalysisGame {
  final String id;
  final String title;
  final String pgn;
  final String moves;
  final String white;
  final String black;
  final String whiteTitle;
  final String blackTitle;
  final int whiteRating;
  final int blackRating;
  final String winner;
  final String speed;
  final GamePlatform platform;
  final DateTime savedAt;

  SavedAnalysisGame({
    required this.id,
    required this.title,
    required this.pgn,
    required this.moves,
    required this.white,
    required this.black,
    this.whiteTitle = '',
    this.blackTitle = '',
    this.whiteRating = 0,
    this.blackRating = 0,
    required this.winner,
    required this.speed,
    required this.platform,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'pgn': pgn,
        'moves': moves,
        'white': white,
        'black': black,
        'whiteTitle': whiteTitle,
        'blackTitle': blackTitle,
        'whiteRating': whiteRating,
        'blackRating': blackRating,
        'winner': winner,
        'speed': speed,
        'platform': platform.name,
        'savedAt': savedAt.toIso8601String(),
      };

  factory SavedAnalysisGame.fromJson(Map<String, dynamic> json) {
    return SavedAnalysisGame(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      pgn: json['pgn'] ?? '',
      moves: json['moves'] ?? '',
      white: json['white'] ?? '',
      black: json['black'] ?? '',
      whiteTitle: json['whiteTitle'] ?? '',
      blackTitle: json['blackTitle'] ?? '',
      whiteRating: json['whiteRating'] ?? 0,
      blackRating: json['blackRating'] ?? 0,
      winner: json['winner'] ?? 'draw',
      speed: json['speed'] ?? '',
      platform: GamePlatform.values.firstWhere(
        (e) => e.name == (json['platform'] ?? 'local'),
        orElse: () => GamePlatform.local,
      ),
      savedAt: DateTime.tryParse(json['savedAt'] ?? '') ?? DateTime.now(),
    );
  }

  static SavedAnalysisGame fromGameEntry(GameEntry g) {
    return SavedAnalysisGame(
      id: '${g.white}_${g.black}_${DateTime.now().millisecondsSinceEpoch}',
      title: '${g.white} vs ${g.black}',
      pgn: g.pgn,
      moves: g.moves,
      white: g.white,
      black: g.black,
      whiteTitle: g.whiteTitle,
      blackTitle: g.blackTitle,
      whiteRating: g.whiteRating,
      blackRating: g.blackRating,
      winner: g.winner,
      speed: g.speed,
      platform: g.platform,
      savedAt: DateTime.now(),
    );
  }
}
