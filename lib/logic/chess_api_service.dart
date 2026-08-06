import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../model/game_analysis_models.dart';

/// Fetches games and player profiles from Lichess and Chess.com.
/// Adapted from MoveLab's _HomePageState (lines 3344–3612, main.dart).
/// No Firebase, no authentication — public API only.
class ChessApiService {
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Accept': 'application/json',
  };

  // ─── Lichess ───────────────────────────────────────────────────────────────

  /// Fetches a Lichess player's profile (ratings).
  /// Returns null if user not found or network error.
  Future<PlayerProfile?> fetchLichessProfile(String username) async {
    try {
      final res = await http
          .get(
            Uri.parse('https://lichess.org/api/user/$username'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return PlayerProfile(
          username: data['username']?.toString() ?? username,
          title: data['title']?.toString() ?? '',
          rapid: data['perfs']?['rapid']?['rating'] as int?,
          blitz: data['perfs']?['blitz']?['rating'] as int?,
          bullet: data['perfs']?['bullet']?['rating'] as int?,
        );
      }
    } catch (e) {
      debugPrint('[ChessApiService] fetchLichessProfile error: $e');
    }
    return null;
  }

  /// Fetches up to [maxGames] games from Lichess for [username].
  /// [tempo] filters by time control ('all', 'blitz', 'rapid', 'bullet', etc.)
  ///
  /// Adapted from MoveLab _fetchLichessGames (line 3548).
  Future<List<GameEntry>> fetchLichessGames(
    String username, {
    String tempo = 'all',
    int maxGames = 30,
  }) async {
    final list = <GameEntry>[];
    try {
      String urlStr =
          'https://lichess.org/api/games/user/$username?max=$maxGames';
      if (tempo != 'all') urlStr += '&perfType=$tempo';

      final res = await http.get(
        Uri.parse(urlStr),
        headers: {
          'User-Agent': _headers['User-Agent']!,
          'Accept': 'application/x-ndjson',
        },
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) {
        for (final line in res.body.trim().split('\n')) {
          if (line.isEmpty) continue;
          try {
            final m = jsonDecode(line) as Map<String, dynamic>;
            final wName =
                m['players']?['white']?['user']?['name']?.toString() ??
                    'Unknown';
            final bName =
                m['players']?['black']?['user']?['name']?.toString() ??
                    'Unknown';

            list.add(GameEntry(
              platform: GamePlatform.lichess,
              white: wName,
              black: bName,
              whiteTitle:
                  m['players']?['white']?['user']?['title']?.toString() ?? '',
              blackTitle:
                  m['players']?['black']?['user']?['title']?.toString() ?? '',
              whiteRating: (m['players']?['white']?['rating'] as int?) ?? 0,
              blackRating: (m['players']?['black']?['rating'] as int?) ?? 0,
              winner: m['winner']?.toString() ?? 'draw',
              speed: m['speed']?.toString().toLowerCase() ?? '',
              pgn: '',
              moves: m['moves']?.toString() ?? '',
              date: m['createdAt'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(
                      m['createdAt'] as int,
                    ).toIso8601String()
                  : '',
            ));
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[ChessApiService] fetchLichessGames error: $e');
    }
    return list;
  }

  /// Autocomplete Lichess usernames (used in Player Insights search).
  Future<List<String>> lichessAutocomplete(String term) async {
    try {
      final res = await http
          .get(
            Uri.parse(
                'https://lichess.org/api/player/autocomplete?term=${Uri.encodeComponent(term)}'),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) return data.cast<String>();
      }
    } catch (_) {}
    return [];
  }

  // ─── Chess.com ─────────────────────────────────────────────────────────────

  /// Fetches a Chess.com player's profile and stats.
  Future<PlayerProfile?> fetchChessComProfile(String username) async {
    try {
      final profileRes = await http
          .get(
            Uri.parse('https://api.chess.com/pub/player/$username'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      final statsRes = await http
          .get(
            Uri.parse('https://api.chess.com/pub/player/$username/stats'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (profileRes.statusCode == 200 && statsRes.statusCode == 200) {
        final pData = jsonDecode(profileRes.body) as Map<String, dynamic>;
        final sData = jsonDecode(statsRes.body) as Map<String, dynamic>;
        return PlayerProfile(
          username: pData['username']?.toString() ?? username,
          title: pData['title']?.toString() ?? '',
          rapid: sData['chess_rapid']?['last']?['rating'] as int?,
          blitz: sData['chess_blitz']?['last']?['rating'] as int?,
          bullet: sData['chess_bullet']?['last']?['rating'] as int?,
        );
      }
    } catch (e) {
      debugPrint('[ChessApiService] fetchChessComProfile error: $e');
    }
    return null;
  }

  /// Fetches up to [maxGames] games from Chess.com for [username].
  /// Adapted from MoveLab _fetchChessComGames (line 3580).
  Future<List<GameEntry>> fetchChessComGames(
    String username, {
    String tempo = 'all',
    int maxGames = 30,
  }) async {
    final list = <GameEntry>[];
    try {
      final archRes = await http
          .get(
            Uri.parse(
                'https://api.chess.com/pub/player/$username/games/archives'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (archRes.statusCode != 200) return list;

      final archives =
          (jsonDecode(archRes.body)['archives'] as List? ?? []).cast<String>();

      for (final url in archives.reversed) {
        if (list.length >= maxGames) break;
        try {
          final gRes = await http
              .get(Uri.parse(url), headers: _headers)
              .timeout(const Duration(seconds: 15));
          if (gRes.statusCode != 200) continue;

          final games =
              (jsonDecode(gRes.body)['games'] as List? ?? []).reversed;

          for (final g in games) {
            if (list.length >= maxGames) break;
            final t = g['time_class']?.toString().toLowerCase() ?? '';
            if (tempo != 'all' && t != tempo) continue;

            list.add(GameEntry(
              platform: GamePlatform.chessCom,
              white: g['white']['username']?.toString() ?? '',
              black: g['black']['username']?.toString() ?? '',
              whiteRating: (g['white']['rating'] as int?) ?? 0,
              blackRating: (g['black']['rating'] as int?) ?? 0,
              winner: _chessComWinner(g),
              speed: t,
              pgn: g['pgn']?.toString() ?? '',
              moves: '',
              whiteAccuracy: (g['accuracies']?['white'] as num?)?.toDouble(),
              blackAccuracy: (g['accuracies']?['black'] as num?)?.toDouble(),
              date: g['end_time'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(
                      (g['end_time'] as int) * 1000,
                    ).toIso8601String()
                  : '',
            ));
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[ChessApiService] fetchChessComGames error: $e');
    }
    return list;
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  String _chessComWinner(Map<String, dynamic> game) {
    final wResult = game['white']['result']?.toString() ?? '';
    final bResult = game['black']['result']?.toString() ?? '';
    if (wResult == 'win') return 'white';
    if (bResult == 'win') return 'black';
    return 'draw';
  }
}
