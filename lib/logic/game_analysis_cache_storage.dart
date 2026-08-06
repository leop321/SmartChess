import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CachedGameAnalysis {
  final String gameKey; // starting FEN + space-separated moves
  final Map<int, double> evalValues;
  final Map<int, String> evalTexts;
  final Map<int, List<String>> evalSuggestions;
  final double whiteAccuracy;
  final double blackAccuracy;

  CachedGameAnalysis({
    required this.gameKey,
    required this.evalValues,
    required this.evalTexts,
    required this.evalSuggestions,
    required this.whiteAccuracy,
    required this.blackAccuracy,
  });

  Map<String, dynamic> toJson() {
    return {
      'gameKey': gameKey,
      'evalValues': evalValues.map((k, v) => MapEntry(k.toString(), v)),
      'evalTexts': evalTexts.map((k, v) => MapEntry(k.toString(), v)),
      'evalSuggestions':
          evalSuggestions.map((k, v) => MapEntry(k.toString(), v)),
      'whiteAccuracy': whiteAccuracy,
      'blackAccuracy': blackAccuracy,
    };
  }

  factory CachedGameAnalysis.fromJson(Map<String, dynamic> json) {
    final valuesMap = json['evalValues'] as Map<String, dynamic>;
    final textsMap = json['evalTexts'] as Map<String, dynamic>;
    final suggsMap = json['evalSuggestions'] as Map<String, dynamic>;

    return CachedGameAnalysis(
      gameKey: json['gameKey'] as String,
      evalValues: valuesMap
          .map((k, v) => MapEntry(int.parse(k), (v as num).toDouble())),
      evalTexts: textsMap.map((k, v) => MapEntry(int.parse(k), v as String)),
      evalSuggestions: suggsMap
          .map((k, v) => MapEntry(int.parse(k), List<String>.from(v as List))),
      whiteAccuracy: (json['whiteAccuracy'] as num).toDouble(),
      blackAccuracy: (json['blackAccuracy'] as num).toDouble(),
    );
  }
}

class GameAnalysisCacheStorage {
  static const String _storageKey = 'game_analysis_cache_v1';

  static Future<List<CachedGameAnalysis>> loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr == null) return [];
      final List<dynamic> list = jsonDecode(jsonStr);
      return list
          .map((e) => CachedGameAnalysis.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveCache(List<CachedGameAnalysis> cache) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(cache.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, jsonStr);
    } catch (_) {}
  }

  static Future<CachedGameAnalysis?> getAnalysis(String gameKey) async {
    final cache = await loadCache();
    for (final entry in cache) {
      if (entry.gameKey == gameKey) {
        return entry;
      }
    }
    return null;
  }

  static Future<void> addAnalysis(CachedGameAnalysis analysis) async {
    var cache = await loadCache();
    // Remove if already exists to update it and move to front
    cache.removeWhere((e) => e.gameKey == analysis.gameKey);
    // Prepend (FIFO / LFU-like but keeping most recent at the front)
    cache.insert(0, analysis);
    if (cache.length > 10) {
      cache = cache.sublist(0, 10);
    }
    await saveCache(cache);
  }
}
