import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:en_passant/logic/chess_board.dart';
import 'package:en_passant/model/puzzle.dart';
import 'package:en_passant/logic/puzzle/uci_move_converter.dart';

void main() {
  group('Lichess Puzzle Adapter Tests', () {
    late ChessBoard board;
    late List<dynamic> fixtureData;

    setUpAll(() {
      final file = File('test/fixtures/lichess_puzzles_sample.json');
      final jsonString = file.readAsStringSync();
      fixtureData = jsonDecode(jsonString) as List<dynamic>;
    });

    setUp(() {
      board = ChessBoard();
    });

    test('Fehlendes Pflichtfeld "puzzle" wirft FormatException', () {
      final invalidJson = {'game': {}};
      expect(
        () => Puzzle.fromLichessJson(invalidJson),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('fehlt Pflichtfeld "puzzle"'))),
      );
    });

    test('Fehlendes Pflichtfeld "game.pgn" wirft FormatException', () {
      final invalidJson = {
        'puzzle': {
          'id': '1',
          'rating': 1500,
          'lastMove': 'e4',
          'solution': ['e5']
        },
        'game': {}
      };
      expect(
        () => Puzzle.fromLichessJson(invalidJson),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('fehlt Pflichtfeld "game.pgn"'))),
      );
    });

    test('Parst gültiges Lichess JSON aus Fixture zu korrektem Puzzle-Objekt',
        () {
      final puzzleMap = fixtureData.first as Map<String, dynamic>;
      final puzzle = Puzzle.fromLichessJson(puzzleMap);

      expect(puzzle.id, '00008');
      expect(puzzle.rating, 1798);
      expect(puzzle.themes, contains('hangingPiece'));
      expect(puzzle.sourceUrl, 'https://lichess.org/training/00008');

      // Die Lösung MUSS den Gegnerzug (f2g3) als ersten Zug enthalten!
      expect(puzzle.solutionMoves.first, 'f2g3');
      expect(puzzle.solutionMoves[1], 'e6e7');
    });

    test('Verifiziert alle 10 Puzzles in der Fixture', () {
      for (var i = 0; i < fixtureData.length; i++) {
        final puzzleMap = fixtureData[i] as Map<String, dynamic>;
        final puzzle = Puzzle.fromLichessJson(puzzleMap);

        // 1. Lade FEN
        board.loadFEN(puzzle.fen);

        // 2. Ersten Zug (Gegnerzug) konvertieren
        final firstUci = puzzle.solutionMoves.first;
        final move = uciToMove(firstUci, board);

        // 3. Prüfen ob Zug legal ist
        final pieceToMove = board.tiles[move.from];
        expect(pieceToMove, isNotNull,
            reason:
                'Puzzle \${puzzle.id} (Index \$i): Keine Figur auf Startfeld des ersten Zugs \$firstUci in FEN \${puzzle.fen}');

        final legalMoves = board.movesForPiece(pieceToMove!, legal: true);
        final isLegal = legalMoves.contains(move.to);

        expect(isLegal, isTrue,
            reason:
                'Puzzle \${puzzle.id} (Index \$i): Der erste Zug \$firstUci ist in der Stellung \${puzzle.fen} nicht legal.');
      }
    });
  });
}
