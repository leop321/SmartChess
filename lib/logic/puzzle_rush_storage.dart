import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../model/puzzle_rush_config.dart';

class PuzzleRushRunRecord {
  final String dateString;
  final int score;
  final int bestStreak;
  final PuzzleRushConfig config;

  PuzzleRushRunRecord({
    required this.dateString,
    required this.score,
    required this.bestStreak,
    required this.config,
  });

  Map<String, dynamic> toJson() => {
        'dateString': dateString,
        'score': score,
        'bestStreak': bestStreak,
        'config': config.toJson(),
      };

  factory PuzzleRushRunRecord.fromJson(Map<String, dynamic> json) =>
      PuzzleRushRunRecord(
        dateString: json['dateString'] as String? ?? '',
        score: json['score'] as int? ?? 0,
        bestStreak: json['bestStreak'] as int? ?? 0,
        config: PuzzleRushConfig.fromJson(
            json['config'] as Map<String, dynamic>? ?? {}),
      );
}

class PuzzleRushStorage {
  static const _keyConfig = 'puzzle_rush_config';
  static const _keyHighScore = 'puzzle_rush_high_score';
  static const _keyBestStreak = 'puzzle_rush_best_streak';
  static const _keyTotalSolved = 'puzzle_rush_total_solved';
  static const _keyHistory = 'puzzle_rush_history';

  static Future<PuzzleRushConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyConfig);
    if (raw == null) return const PuzzleRushConfig();
    try {
      return PuzzleRushConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const PuzzleRushConfig();
    }
  }

  static Future<void> saveConfig(PuzzleRushConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyConfig, jsonEncode(config.toJson()));
  }

  static Future<int> loadHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyHighScore) ?? 0;
  }

  static Future<int> loadBestStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyBestStreak) ?? 0;
  }

  static Future<int> loadTotalSolved() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyTotalSolved) ?? 0;
  }

  static Future<void> saveRunRecord({
    required int score,
    required int bestStreak,
    required PuzzleRushConfig config,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final currentHigh = prefs.getInt(_keyHighScore) ?? 0;
    if (score > currentHigh) {
      await prefs.setInt(_keyHighScore, score);
    }

    final currentStreak = prefs.getInt(_keyBestStreak) ?? 0;
    if (bestStreak > currentStreak) {
      await prefs.setInt(_keyBestStreak, bestStreak);
    }

    final total = prefs.getInt(_keyTotalSolved) ?? 0;
    await prefs.setInt(_keyTotalSolved, total + score);

    final historyJson = prefs.getStringList(_keyHistory) ?? [];
    final now = DateTime.now();
    final dateStr =
        '${now.day}.${now.month}.${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final record = PuzzleRushRunRecord(
      dateString: dateStr,
      score: score,
      bestStreak: bestStreak,
      config: config,
    );

    historyJson.insert(0, jsonEncode(record.toJson()));
    if (historyJson.length > 20) {
      historyJson.removeRange(20, historyJson.length);
    }
    await prefs.setStringList(_keyHistory, historyJson);
  }

  static Future<List<PuzzleRushRunRecord>> loadRunHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_keyHistory) ?? [];
    final List<PuzzleRushRunRecord> records = [];
    for (final raw in rawList) {
      try {
        records.add(PuzzleRushRunRecord.fromJson(
            jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {}
    }
    return records;
  }
}
