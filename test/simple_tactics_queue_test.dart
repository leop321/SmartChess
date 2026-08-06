import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:en_passant/logic/simple_tactics_queue.dart';
import 'package:en_passant/model/tactics_task.dart';
import 'package:en_passant/logic/chess_board.dart';
import 'package:en_passant/logic/game_controller.dart';
import 'package:en_passant/model/app_model.dart';
import 'package:en_passant/model/player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SimpleTacticsQueue Unit Tests', () {
    test('1. Queue holds exactly 3 tasks and refills when completed', () async {
      final queue = SimpleTacticsQueue();
      await queue.restore(TacticsMode.classic);

      expect(queue.queue.length, 3);
      final firstTask = queue.current;
      expect(firstTask, isNotNull);

      // Advance to next task
      final nextTask = await queue.advance(TacticsMode.classic);
      expect(nextTask, isNotNull);
      expect(queue.queue.length, 3);
      expect(nextTask!.id, isNot(equals(firstTask!.id)));
    });

    test('2. Persistence across restarts (restore exact 3 tasks)', () async {
      final queue1 = SimpleTacticsQueue();
      await queue1.restore(TacticsMode.classic);

      final originalIds = queue1.queue.map((t) => t.id).toList();
      expect(originalIds.length, 3);

      // Advance 1 puzzle
      await queue1.advance(TacticsMode.classic);
      final updatedIds = queue1.queue.map((t) => t.id).toList();

      // Create a fresh queue instance simulating app restart
      final queue2 = SimpleTacticsQueue();
      await queue2.restore(TacticsMode.classic);

      final restoredIds = queue2.queue.map((t) => t.id).toList();
      expect(restoredIds, equals(updatedIds));
    });

    test('3. Fresh board instance generation on FEN load (no ghost pieces)',
        () {
      final appModel = AppModel();
      final controller = GameController(appModel);

      // Load FEN 1
      const fen1 =
          'r3k2r/pp3ppp/2n1p3/3p4/3P4/2PB1N2/PP3PPP/R3K2R w KQkq - 0 1';
      controller.loadFEN(fen1);

      final pieceCount1 = controller.board.player1Pieces.length +
          controller.board.player2Pieces.length;
      final turn1 = appModel.turn;

      // Load FEN 2
      const fen2 = '5rk1/1p3ppp/pq3b2/8/8/1P1Q1N2/P4PPP/3R2K1 w - - 2 27';
      controller.loadFEN(fen2);

      final pieceCount2 = controller.board.player1Pieces.length +
          controller.board.player2Pieces.length;
      final turn2 = appModel.turn;

      expect(pieceCount1, isNot(equals(pieceCount2)));
      expect(controller.board.moveStack.isEmpty, true);
      expect(controller.board.redoStack.isEmpty, true);
      expect(controller.selectedPiece, isNull);
      expect(controller.validMoves.isEmpty, true);
    });
  });
}
