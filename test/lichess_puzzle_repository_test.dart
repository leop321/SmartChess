import 'package:en_passant/logic/puzzle/lichess_puzzle_client.dart';
import 'package:en_passant/logic/puzzle/lichess_puzzle_repository.dart';
import 'package:en_passant/model/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

class MockLichessPuzzleClient implements LichessPuzzleClient {
  @override
  Future<Puzzle> fetchDailyPuzzle() async {
    throw UnimplementedError();
  }

  @override
  Future<Puzzle> fetchPuzzleById(String id) async {
    return Puzzle(
      id: id,
      fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      solutionMoves: ['e2e4'],
      rating: 1500,
      themes: [],
    );
  }
}

void main() {
  test('LichessPuzzleRepository rotiert durch 10 IDs ohne Wiederholungen', () async {
    final mockClient = MockLichessPuzzleClient();
    final repo = LichessPuzzleRepository(client: mockClient);

    final Set<String> seenIds = {};

    // Die ersten 10 Aufrufe müssen 10 unterschiedliche IDs liefern
    for (int i = 0; i < 10; i++) {
      final puzzle = await repo.getNextPuzzle();
      expect(seenIds.contains(puzzle.id), isFalse, reason: 'Puzzle ${puzzle.id} wurde wiederholt (Index $i)');
      seenIds.add(puzzle.id);
    }

    expect(seenIds.length, 10);

    // Der 11. Aufruf muss wieder die erste ID liefern (die wir nicht mehr kennen, aber wir checken, ob sie schon gesehen wurde)
    // Wir können auch einfach die erste ID nochmal separat speichern.
  });

  test('LichessPuzzleRepository startet beim 11. Aufruf wieder mit der ersten ID', () async {
    final mockClient = MockLichessPuzzleClient();
    final repo = LichessPuzzleRepository(client: mockClient);

    final puzzle1 = await repo.getNextPuzzle();
    for (int i = 0; i < 9; i++) {
      await repo.getNextPuzzle();
    }
    final puzzle11 = await repo.getNextPuzzle();

    expect(puzzle11.id, puzzle1.id, reason: 'Der 11. Aufruf lieferte nicht das 1. Puzzle');
  });
}
