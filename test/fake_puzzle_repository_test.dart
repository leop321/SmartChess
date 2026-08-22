import 'package:flutter_test/flutter_test.dart';
import 'package:en_passant/logic/chess_board.dart';
import 'package:en_passant/logic/puzzle/fake_puzzle_repository.dart';
import 'package:en_passant/logic/puzzle/puzzle_repository.dart';
import 'package:en_passant/logic/puzzle/uci_move_converter.dart';

void main() {
  group('FakePuzzleRepository Tests', () {
    late PuzzleRepository repo;
    late ChessBoard board;

    setUp(() {
      repo = FakePuzzleRepository();
      board = ChessBoard();
    });

    test('getNextPuzzle gibt Puzzles zurück und rotiert', () async {
      final puzzle1 = await repo.getNextPuzzle();
      expect(puzzle1.id, 'fake-1');

      final puzzle2 = await repo.getNextPuzzle();
      expect(puzzle2.id, 'fake-2');

      final puzzle3 = await repo.getNextPuzzle();
      expect(puzzle3.id, 'fake-3');

      final puzzle4 = await repo.getNextPuzzle();
      expect(puzzle4.id, 'fake-1'); // Rotation
    });

    test('Puzzles haben gültige Start-FENs und der erste Zug ist legal',
        () async {
      // Teste alle 3 Puzzles
      for (int i = 0; i < 3; i++) {
        final puzzle = await repo.getNextPuzzle();

        // 1. FEN laden
        board.loadFEN(puzzle.fen);

        // 2. Ersten Zug (Gegnerzug) aus solutionMoves holen
        final firstUci = puzzle.solutionMoves.first;
        final move = uciToMove(firstUci, board);

        // 3. Prüfen, ob der Zug generiert wird (legal ist)
        final pieceToMove = board.tiles[move.from];
        expect(pieceToMove, isNotNull,
            reason: 'Keine Figur auf Startfeld des ersten Zugs $firstUci');

        final legalMoves = board.movesForPiece(pieceToMove!, legal: true);

        bool isLegal = legalMoves.contains(move.to);

        expect(isLegal, isTrue,
            reason:
                'Der erste Zug $firstUci im Puzzle ${puzzle.id} ist in der Stellung ${puzzle.fen} nicht legal.');
      }
    });
  });
}
