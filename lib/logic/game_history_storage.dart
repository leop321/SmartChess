import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../model/completed_game.dart';

const String _gameHistoryKey = 'chess_game_history';

class GameHistoryStorage {
  static SharedPreferences? _prefs;

  static Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  static Future<void> saveGame(CompletedGame game) async {
    final prefs = await _getPrefs();
    final List<String> currentHistory =
        prefs.getStringList(_gameHistoryKey) ?? [];

    // Convert new game to JSON string
    final gameJson = jsonEncode(game.toJson());

    // Add to beginning of list
    currentHistory.insert(0, gameJson);

    // Keep only the last 20 games to avoid filling up storage
    if (currentHistory.length > 20) {
      currentHistory.removeRange(20, currentHistory.length);
    }

    await prefs.setStringList(_gameHistoryKey, currentHistory);
  }

  static Future<List<CompletedGame>> loadGameHistory() async {
    final prefs = await _getPrefs();
    final List<String> historyStrings =
        prefs.getStringList(_gameHistoryKey) ?? [];

    final List<CompletedGame> games = [];
    for (final gameStr in historyStrings) {
      try {
        games.add(CompletedGame.fromJson(jsonDecode(gameStr)));
      } catch (e) {
        // Skip invalid entries
        print('Error parsing game history entry: $e');
      }
    }
    return games;
  }

  static Future<void> clearHistory() async {
    final prefs = await _getPrefs();
    await prefs.remove(_gameHistoryKey);
  }
}
