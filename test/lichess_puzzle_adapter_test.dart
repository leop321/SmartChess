import 'dart:convert';
import 'dart:io';

import 'package:en_passant/logic/chess_board.dart';
import 'package:en_passant/logic/puzzle/uci_move_converter.dart';
import 'package:en_passant/model/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final file = File('test/fixtures/lichess_puzzles_sample.json');
  final jsonString = file.readAsStringSync();
  final fixtureData = jsonDecode(jsonString) as List<dynamic>;

  group('Lichess Puzzle Adapter Tests', () {
    late ChessBoard board;

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
      final expectedId = puzzleMap['puzzle']['id'].toString();
      final expectedRating = puzzleMap['puzzle']['rating'] as int;
      final expectedFirstMove = puzzleMap['puzzle']['solution'][0].toString();
      final expectedLastMove = puzzleMap['puzzle']['lastMove'].toString();

      final puzzle = Puzzle.fromLichessJson(puzzleMap);

      expect(puzzle.id, expectedId);
      expect(puzzle.rating, expectedRating);
      expect(puzzle.sourceUrl, 'https://lichess.org/training/$expectedId');

      // Die Lösung MUSS den Gegnerzug (lastMove) als ersten Zug enthalten!
      expect(puzzle.solutionMoves.first, expectedLastMove);
      expect(puzzle.solutionMoves[1], expectedFirstMove);
    });

    // Dynamische Generierung von Einzeltests pro Puzzle
    for (var i = 0; i < fixtureData.length; i++) {
      final puzzleMap = fixtureData[i] as Map<String, dynamic>;
      final id = puzzleMap['puzzle']['id'];

      test('Puzzle $id (Index $i) ist FEN-konsistent und erster Zug ist legal',
          () {
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
                'Keine Figur auf Startfeld des ersten Zugs $firstUci in FEN ${puzzle.fen}');

        final legalMoves = board.movesForPiece(pieceToMove!, legal: true);
        final isLegal = legalMoves.contains(move.to);

        expect(isLegal, isTrue,
            reason:
                'Der erste Zug $firstUci ist in der Stellung ${puzzle.fen} nicht legal.');
      });
    }
  });
}
