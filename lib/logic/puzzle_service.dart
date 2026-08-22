import 'dart:convert';
import 'package:http/http.dart' as http;
import '../model/puzzle_model.dart';

class PuzzleService {
  static const String _baseUrl = 'https://lichess.org/api/puzzle';

  Future<PuzzleModel> getDailyPuzzle() async {
    final response = await http.get(Uri.parse('$_baseUrl/daily'));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return PuzzleModel.fromJson(json);
    } else {
      throw Exception('Failed to load daily puzzle');
    }
  }

  // To fetch a random puzzle or a puzzle by ID if needed
  Future<PuzzleModel> getPuzzleById(String id) async {
    final response = await http.get(Uri.parse('$_baseUrl/$id'));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return PuzzleModel.fromJson(json);
    } else {
      throw Exception('Failed to load puzzle $id');
    }
  }
}
