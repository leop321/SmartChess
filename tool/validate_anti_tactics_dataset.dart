import 'dart:convert';
import 'dart:io';
import 'package:chess/chess.dart' as ch;

void main() {
  final file = File('assets/data/anti_tactics_tasks.json');
  if (!file.existsSync()) {
    print('Error: assets/data/anti_tactics_tasks.json does not exist.');
    exit(1);
  }

  try {
    final content = file.readAsStringSync();
    final json = jsonDecode(content);
    if (json is! List) {
      print('Error: JSON is not a list.');
      exit(1);
    }

    print('Validating ${json.length} tasks...');
    int invalidCount = 0;

    for (int i = 0; i < json.length; i++) {
      final item = json[i];
      final id = item['id'] ?? 'unknown_index_$i';
      final fen = item['fen'];
      final difficulty = item['difficulty'];
      final type = item['antiTacticsType'];
      final expectedMoves = item['expectedMoves'];

      print('[$id] FEN: "$fen"');

      if (fen == null || fen.toString().trim().isEmpty) {
        print('  -> FAIL: FEN is empty');
        invalidCount++;
        continue;
      }

      final cleanFen = fen.toString().trim();

      // Check if it's a completely empty board FEN
      final fenParts = cleanFen.split(' ');
      if (fenParts.isEmpty || fenParts[0] == '8/8/8/8/8/8/8/8') {
        print('  -> FAIL: FEN represents an empty board');
        invalidCount++;
        continue;
      }

      // Check validation with chess package
      final validation = ch.Chess.validate_fen(cleanFen);
      if (validation['valid'] != true) {
        print('  -> FAIL: Invalid FEN structure: ${validation['error']}');
        invalidCount++;
        continue;
      }

      try {
        final board = ch.Chess.fromFEN(cleanFen);
        // Ensure there are actually pieces on the board
        int pieceCount = 0;
        for (int square = 0; square < 128; square++) {
          if ((square & 0x88) == 0) {
            // Convert to algebraic representation for the chess package
            final file = square & 7;
            final rank = (square >> 4) & 7;
            final squareName = ch.Chess.SQUARES.keys.elementAt(rank * 8 + file);
            final piece = board.get(squareName);
            if (piece != null) {
              pieceCount++;
            }
          }
        }
        if (pieceCount == 0) {
          print('  -> FAIL: Board has 0 pieces');
          invalidCount++;
          continue;
        }
      } catch (e) {
        print('  -> FAIL: Chess.fromFEN threw an exception: $e');
        invalidCount++;
        continue;
      }

      if (difficulty == null || difficulty is! int || difficulty <= 0) {
        print('  -> FAIL: Invalid difficulty "$difficulty"');
        invalidCount++;
        continue;
      }

      if (type == null ||
          (type != 'winningTacticExists' && type != 'noWinningTactic')) {
        print('  -> FAIL: Invalid antiTacticsType "$type"');
        invalidCount++;
        continue;
      }

      if (expectedMoves == null || expectedMoves is! List) {
        print('  -> FAIL: Invalid expectedMoves "$expectedMoves"');
        invalidCount++;
        continue;
      }

      print('  -> OK');
    }

    print('Validation complete. $invalidCount invalid tasks found.');
  } catch (e) {
    print('Error reading or parsing JSON: $e');
    exit(1);
  }
}
