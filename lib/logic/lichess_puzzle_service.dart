import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../model/lichess_puzzle.dart';

/// Fetches puzzles from the Lichess public API.
///
/// Endpoints used (no authentication required):
///   GET https://lichess.org/api/puzzle/next   — random puzzle
///   GET https://lichess.org/api/puzzle/daily  — daily puzzle
class LichessPuzzleService {
  static const _baseUrl = 'https://lichess.org/api/puzzle';
  static const _timeout = Duration(seconds: 10);

  final http.Client _client;

  LichessPuzzleService({http.Client? client})
      : _client = client ?? http.Client();

  /// Returns a random puzzle from the Lichess database.
  Future<LichessPuzzle> fetchNextPuzzle() async {
    return _fetch('$_baseUrl/next');
  }

  /// Returns the daily puzzle from Lichess.
  Future<LichessPuzzle> fetchDailyPuzzle() async {
    return _fetch('$_baseUrl/daily');
  }

  /// Returns a specific puzzle by its Lichess ID.
  Future<LichessPuzzle> fetchPuzzleById(String id) async {
    return _fetch('$_baseUrl/$id');
  }

  Future<LichessPuzzle> _fetch(String url) async {
    try {
      final headers = <String, String>{
        'Accept': 'application/json',
      };
      if (!kIsWeb) {
        headers['User-Agent'] =
            'ChessApp/1.0 (Flutter App; contact@chessapp.internal)';
      }

      final response = await _client
          .get(
            Uri.parse(url),
            headers: headers,
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return LichessPuzzle.fromJson(data);
      } else {
        throw LichessApiException(
            'HTTP ${response.statusCode}: ${response.body}');
      }
    } on LichessApiException {
      rethrow;
    } catch (e) {
      throw LichessApiException('Network error: $e');
    }
  }
}

class LichessApiException implements Exception {
  final String message;
  const LichessApiException(this.message);

  @override
  String toString() => 'LichessApiException: $message';
}
