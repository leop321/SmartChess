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
    final puzzle = json['puzzle'] as Map<String, dynamic>? ?? json;
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
    // 2. Replay game PGN using robust forward step-by-step replay up to (initialPly + 1)
    else if (game != null && game['pgn'] != null) {
      pgnStr = game['pgn'] as String;
      final initialPly = puzzle['initialPly'] as int?;
      final replayResult = _replayPgnToTargetPly(
          pgnStr, initialPly != null ? initialPly + 1 : null);
      if (replayResult != null) {
        rawFen = replayResult.fen;
        lastMove = replayResult.lastMove;
      }
    } else {
      rawFen = (puzzle['fen'] as String? ?? '').trim();
      pgnStr = json['pgn'] as String?;
      lastMove = puzzle['lastMove'] as String?;
    }

    // Ensure 6 standard FEN components
    if (rawFen.isNotEmpty) {
      final parts = rawFen.split(RegExp(r'\s+'));
      if (parts.length == 4) {
        rawFen = '$rawFen 0 1';
      } else if (parts.length == 5) {
        rawFen = '$rawFen 1';
      }
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

  /// Replays a PGN forward move by move up to [targetPly] (1-indexed count of half-moves).
  static _PgnReplayResult? _replayPgnToTargetPly(String pgn, int? targetPly) {
    try {
      final board = ch.Chess();
      // Clean comments, clocks, evaluations, variations, and game results
      final cleaned = pgn
          .replaceAll(RegExp(r'\[.*?\]'), ' ') // headers
          .replaceAll(RegExp(r'\{.*?\}'), ' ') // comments / clocks / evals
          .replaceAll(RegExp(r'\([^)]*\)'), ' ') // variations
          .replaceAll(RegExp(r'\$\d+'), ' ') // NAGs
          .replaceAll(RegExp(r'(1-0|0-1|1\/2-1\/2|\*)'), ' ') // results
          .replaceAll(RegExp(r'\d+\.+'), ' '); // move numbers (e.g. 1. or 1...)

      final tokens = cleaned
          .split(RegExp(r'\s+'))
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      int currentPly = 0;
      String? lastUci;

      for (final san in tokens) {
        final ok = board.move(san);
        if (!ok) break;
        currentPly++;

        // Extract UCI representation of the move just played
        if (board.history.isNotEmpty) {
          final lastState = board.history.last;
          final m = lastState.move;
          final promo = m.promotion?.name.toLowerCase() ?? '';
          lastUci = '${m.fromAlgebraic}${m.toAlgebraic}$promo';
        }

        if (targetPly != null && currentPly >= targetPly) {
          break;
        }
      }

      if (currentPly == 0 && targetPly != null && targetPly > 0) {
        return null;
      }

      return _PgnReplayResult(fen: board.fen, lastMove: lastUci);
    } catch (_) {
      return null;
    }
  }

  /// Validates that the FEN is legal and all solution moves can be executed legally in sequence.
  bool get isValidPuzzle {
    if (fen.isEmpty || solution.isEmpty) return false;
    try {
      final validation = ch.Chess.validate_fen(fen);
      if (validation['valid'] != true) return false;

      final board = ch.Chess.fromFEN(fen);
      if (board.fen.isEmpty) return false;

      // Ensure both kings exist on the board
      int whiteKings = 0;
      int blackKings = 0;
      for (final sq in ch.Chess.SQUARES.keys) {
        final p = board.get(sq);
        if (p != null && p.type == ch.PieceType.KING) {
          if (p.color == ch.Color.WHITE) {
            whiteKings++;
          } else {
            blackKings++;
          }
        }
      }
      if (whiteKings != 1 || blackKings != 1) return false;

      // Verify every move in solution can be executed legally
      for (final uci in solution) {
        if (uci.length < 4) return false;
        final from = uci.substring(0, 2);
        final to = uci.substring(2, 4);
        final promo = uci.length > 4 ? uci.substring(4) : null;
        final moveArgs = <String, String>{'from': from, 'to': to};
        if (promo != null) moveArgs['promotion'] = promo;
        final ok = board.move(moveArgs);
        if (!ok) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

class _PgnReplayResult {
  final String fen;
  final String? lastMove;
  const _PgnReplayResult({required this.fen, this.lastMove});
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

  static String _getRecentIdsKey(String mode) => 'tacticsRecentSeenIds_$mode';

  /// Loads recent seen puzzle IDs across app restarts (max 50).
  static Future<List<String>> loadRecentPuzzleIds(
      {String mode = 'classic'}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_getRecentIdsKey(mode)) ?? [];
  }

  /// Saves recent seen puzzle IDs across app restarts.
  static Future<void> saveRecentPuzzleIds(List<String> ids,
      {String mode = 'classic'}) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = ids.length > 50 ? ids.sublist(ids.length - 50) : ids;
    await prefs.setStringList(_getRecentIdsKey(mode), trimmed);
  }
}
