import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../model/puzzle.dart';

class PuzzleNetworkException implements Exception {
  final String message;
  PuzzleNetworkException(this.message);
  @override
  String toString() => 'PuzzleNetworkException: $message';
}

class PuzzleServerException implements Exception {
  final int statusCode;
  final String message;
  PuzzleServerException(this.statusCode, this.message);
  @override
  String toString() => 'PuzzleServerException: $statusCode $message';
}

class PuzzleParseException implements Exception {
  final String message;
  PuzzleParseException(this.message);
  @override
  String toString() => 'PuzzleParseException: $message';
}

/// Client zum Abrufen von Puzzles über die offizielle Lichess API.
class LichessPuzzleClient {
  static const String baseUrl = 'https://lichess.org/api/puzzle';
  final http.Client _client;

  LichessPuzzleClient({http.Client? client})
      : _client = client ?? http.Client();

  /// Holt das tagesaktuelle Puzzle ("Daily Puzzle").
  Future<Puzzle> fetchDailyPuzzle() async {
    return _fetchPuzzle('$baseUrl/daily');
  }

  /// Holt ein spezifisches Puzzle anhand seiner ID.
  Future<Puzzle> fetchPuzzleById(String id) async {
    return _fetchPuzzle('$baseUrl/$id');
  }

  Future<Puzzle> _fetchPuzzle(String url) async {
    try {
      final response = await _client.get(Uri.parse(url)).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          throw PuzzleNetworkException('Timeout beim Abrufen des Puzzles.');
        },
      );

      if (response.statusCode >= 400) {
        throw PuzzleServerException(
            response.statusCode, 'HTTP-Fehler beim Abrufen von $url');
      }

      final Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body);
      } catch (e) {
        throw PuzzleParseException('Ungültiges JSON von Lichess erhalten: $e');
      }

      return Puzzle.fromLichessJson(json);
    } on PuzzleNetworkException {
      rethrow;
    } on PuzzleServerException {
      rethrow;
    } on PuzzleParseException {
      rethrow;
    } catch (e) {
      throw PuzzleNetworkException('Netzwerkfehler: $e');
    }
  }
}
