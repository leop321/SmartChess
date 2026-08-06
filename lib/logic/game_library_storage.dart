import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/game_analysis_models.dart';

/// Local game library backed by SharedPreferences.
/// Adapted from MoveLab's GlobalLibrary (lines 904–979, main.dart)
/// — Firebase / cloud sync removed, local-only.
class GameLibraryStorage {
  static const _key = 'analysis_library_games';

  List<SavedAnalysisGame> _games = [];

  List<SavedAnalysisGame> get games => List.unmodifiable(_games);

  // ─── Load ──────────────────────────────────────────────────────────────────

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? [];
      _games =
          raw.map((e) => SavedAnalysisGame.fromJson(jsonDecode(e))).toList();
      // Newest first
      _games.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    } catch (e) {
      debugPrint('[GameLibraryStorage] load error: $e');
    }
  }

  // ─── Save ──────────────────────────────────────────────────────────────────

  Future<void> add(SavedAnalysisGame game) async {
    _games.insert(0, game);
    await _persist();
  }

  Future<void> remove(String id) async {
    _games.removeWhere((g) => g.id == id);
    await _persist();
  }

  bool isSaved(String pgn, String moves) {
    if (pgn.isEmpty && moves.isEmpty) return false;
    if (pgn.isNotEmpty) return _games.any((g) => g.pgn == pgn);
    return _games.any((g) => g.moves == moves);
  }

  // ─── Internal ─────────────────────────────────────────────────────────────

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = _games.map((g) => jsonEncode(g.toJson())).toList();
      await prefs.setStringList(_key, raw);
    } catch (e) {
      debugPrint('[GameLibraryStorage] persist error: $e');
    }
  }
}
