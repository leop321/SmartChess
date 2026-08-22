import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../model/puzzle.dart';

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
          throw Exception('Netzwerk-Timeout beim Abrufen des Puzzles.');
        },
      );

      if (response.statusCode >= 400) {
        throw Exception(
            'HTTP-Fehler ${response.statusCode} beim Abrufen von $url');
      }

      final Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body);
      } catch (e) {
        throw FormatException('Ungültiges JSON von Lichess erhalten: $e');
      }

      return Puzzle.fromLichessJson(json);
    } on FormatException {
      rethrow; // Parse-Fehler nach oben durchreichen
    } catch (e) {
      if (e is Exception && e.toString().contains('HTTP-Fehler') ||
          e.toString().contains('Timeout')) {
        rethrow;
      }
      throw Exception('Netzwerkfehler: $e');
    }
  }
}
