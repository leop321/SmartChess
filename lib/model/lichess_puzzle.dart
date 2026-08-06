import 'package:chess/chess.dart' as ch;
import 'package:shared_preferences/shared_preferences.dart';

/// A record of a single completed (or resigned) tactics puzzle.
class PuzzleRecord {
  final String puzzleId;
  final int ratingChange;
  final bool solved; // false = resigned
  final int elapsedSeconds;

  const PuzzleRecord({
    required this.puzzleId,
    required this.ratingChange,
    required this.solved,
    required this.elapsedSeconds,
  });

  String toSerializedString() =>
      '$puzzleId|$ratingChange|${solved ? 1 : 0}|$elapsedSeconds';

  factory PuzzleRecord.fromSerializedString(String s) {
    final parts = s.split('|');
    if (parts.length < 3) throw const FormatException('Invalid PuzzleRecord');
    return PuzzleRecord(
      puzzleId: parts[0],
      ratingChange: int.parse(parts[1]),
      solved: parts[2] == '1',
      elapsedSeconds: parts.length > 3
          ? int.parse(parts[3])
          : 0, // Fallback for old local records
    );
  }
}

/// Lightweight data class representing a single Lichess puzzle.
class LichessPuzzle {
  final String id;

  /// The FEN after the opponent's last move — the position from which
  /// the player must find the solution.
  final String fen;

  /// The full solution as a list of UCI moves, e.g. ["e2e4", "d7d5"].
  /// The first move is always the player's move.
  final List<String> solution;

  /// Lichess puzzle rating.
  final int rating;

  /// Semantic tags e.g. ["fork", "skewer", "endgame"].
  final List<String> themes;

  /// The opponent's last move (the move that set up the puzzle).
  final String? lastMove;
  final String? pgn;

  const LichessPuzzle({
    required this.id,
    required this.fen,
    required this.solution,
    required this.rating,
    required this.themes,
    this.lastMove,
    this.pgn,
  });

  factory LichessPuzzle.fromJson(Map<String, dynamic> json) {
    final puzzle = json['puzzle'] as Map<String, dynamic>;
    final game = json['game'] as Map<String, dynamic>?;

    String rawFen = '';
    String? lastMove;
    String? pgnStr;

    // 1. Prefer explicit FEN if provided in puzzle object
    final explicitFen = puzzle['fen'] as String?;
    if (explicitFen != null && explicitFen.trim().isNotEmpty) {
      rawFen = explicitFen.trim();
      lastMove = puzzle['lastMove'] as String?;
      pgnStr = json['pgn'] as String? ?? game?['pgn'] as String?;
    }
    // 2. Replay game PGN up to initialPly (the opponent's setup move)
    else if (game != null && game['pgn'] != null) {
      pgnStr = game['pgn'] as String;
      final initialPly = puzzle['initialPly'] as int?;
      final pgnMoves =
          pgnStr.split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
      final board = ch.Chess();

      final limit = (initialPly != null && initialPly < pgnMoves.length)
          ? initialPly + 1
          : pgnMoves.length;

      for (int i = 0; i < limit; i++) {
        board.move(pgnMoves[i]);
      }
      rawFen = board.fen;

      if (limit > 0) {
        final last = board.undo();
        if (last != null) {
          final from = last['from'] as String?;
          final to = last['to'] as String?;
          final promo = last['promotion'] as String?;
          if (from != null && to != null) {
            lastMove = '$from$to${promo ?? ''}';
          }
          board.move(last);
          rawFen = board.fen;
        }
      }
    } else {
      rawFen = (puzzle['fen'] as String? ?? '').trim();
      pgnStr = json['pgn'] as String?;
      lastMove = puzzle['lastMove'] as String?;
    }

    final parts = rawFen.split(RegExp(r'\s+'));
    if (parts.length == 4) {
      rawFen = '$rawFen 0 1';
    } else if (parts.length == 5) {
      rawFen = '$rawFen 1';
    }

    return LichessPuzzle(
      id: puzzle['id'] as String? ?? '',
      fen: rawFen,
      solution: List<String>.from(puzzle['solution'] as List? ?? []),
      rating: puzzle['rating'] as int? ?? 1500,
      themes: List<String>.from(puzzle['themes'] as List? ?? []),
      lastMove: lastMove,
      pgn: pgnStr,
    );
  }
}

/// Persistent storage for the tactics rating and session history.
class TacticsStorage {
  static String _getRatingKey(String mode) => 'userRatingTactics_$mode';
  static String _getHistoryKey(String mode) => 'tacticsSessionHistory_$mode';
  static const _showTimerKey = 'tacticsShowTimer';
  static const _ratingOffsetKey = 'tacticsRatingOffset';

  /// Loads the persisted tactics rating offset (defaults to 0).
  static Future<int> loadRatingOffset() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_ratingOffsetKey) ?? 0;
  }

  /// Saves the tactics rating offset.
  static Future<void> saveRatingOffset(int offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_ratingOffsetKey, offset);
  }

  /// Loads the persisted tactics rating (defaults to 1200).
  static Future<int> loadRating({String mode = 'classic'}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_getRatingKey(mode)) ?? 1200;
  }

  /// Saves the tactics rating.
  static Future<void> saveRating(int rating, {String mode = 'classic'}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_getRatingKey(mode), rating);
  }

  /// Loads the show timer setting.
  static Future<bool> loadShowTimer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showTimerKey) ?? true;
  }

  /// Saves the show timer setting.
  static Future<void> saveShowTimer(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showTimerKey, show);
  }

  /// Loads the session history (persisted across restarts, max 50 entries).
  static Future<List<PuzzleRecord>> loadHistory(
      {String mode = 'classic'}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_getHistoryKey(mode)) ?? [];
    return raw
        .map((s) {
          try {
            return PuzzleRecord.fromSerializedString(s);
          } catch (_) {
            return null;
          }
        })
        .whereType<PuzzleRecord>()
        .toList();
  }

  /// Saves the session history.
  static Future<void> saveHistory(List<PuzzleRecord> history,
      {String mode = 'classic'}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = history.map((r) => r.toSerializedString()).toList();
    await prefs.setStringList(_getHistoryKey(mode), raw);
  }
}
