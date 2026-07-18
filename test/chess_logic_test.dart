import 'package:en_passant/chess_engine/chess_logic/chess_state.dart';
import 'package:en_passant/chess_engine/chess_logic/move_parser.dart';
import 'package:en_passant/chess_engine/puzzles/puzzle.dart';
import 'package:en_passant/chess_engine/puzzles/puzzle_manager.dart';
import 'package:en_passant/chess_engine/speech/speech_service.dart';
import 'package:flutter_test/flutter_test.dart';

class MockSpeechService extends ChessSpeechService {
  final List<List<String>> playedTokenSequences = [];

  @override
  Future<void> playMove(List<String> tokens) async {
    playedTokenSequences.add(tokens);
  }

  @override
  void dispose() {}
}

void main() {
  group('MoveParser Tests', () {
    test('Parse standard pawn move', () {
      expect(MoveParser.parseSan('e4'), equals(['e', '4']));
    });

    test('Parse knight move', () {
      expect(MoveParser.parseSan('Nf3'), equals(['knight', 'f', '3']));
    });

    test('Parse capture with piece', () {
      expect(MoveParser.parseSan('Nxd4'), equals(['knight', 'takes', 'd', '4']));
    });

    test('Parse pawn capture', () {
      expect(MoveParser.parseSan('exd5'), equals(['e', 'takes', 'd', '5']));
    });

    test('Parse short castle', () {
      expect(MoveParser.parseSan('O-O'), equals(['castle']));
    });

    test('Parse long castle', () {
      expect(MoveParser.parseSan('O-O-O'), equals(['long_castle']));
    });

    test('Parse check and checkmate symbols are removed', () {
      expect(MoveParser.parseSan('Qxf7#'), equals(['queen', 'takes', 'f', '7']));
      expect(MoveParser.parseSan('Bxf7+'), equals(['bishop', 'takes', 'f', '7']));
    });

    test('Parse pawn promotion', () {
      expect(MoveParser.parseSan('e8=Q'), equals(['e', '8', 'queen']));
      expect(MoveParser.parseSan('exd8=N#'), equals(['e', 'takes', 'd', '8', 'knight']));
    });

    test('Parse disambiguated moves', () {
      expect(MoveParser.parseSan('Nbd2'), equals(['knight', 'd', '2']));
      expect(MoveParser.parseSan('R1e2'), equals(['rook', 'e', '2']));
    });
  });

  group('ChessState Tests', () {
    test('Initialize starting board FEN', () {
      final state = ChessState();
      expect(state.fen.startsWith('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR'), isTrue);
    });

    test('Make legal move and get SAN history', () {
      final state = ChessState();
      final san = state.makeMove('e2e4');
      expect(san, equals('e4'));
      expect(state.fen.contains('4P3'), isTrue);
    });

    test('Make illegal move returns null', () {
      final state = ChessState();
      final san = state.makeMove('e2e5'); // Illegal first move for pawn
      expect(san, isNull);
    });
  });

  group('PuzzleManager Tests', () {
    late MockSpeechService mockSpeech;
    late PuzzleManager manager;

    setUp(() {
      mockSpeech = MockSpeechService();
      manager = PuzzleManager(mockSpeech);
    });

    test('Load puzzle and verify starting state', () {
      const puzzle = ChessPuzzle(
        id: 'test_puzzle',
        startingFen: '6k1/5ppp/8/8/8/8/3R4/6K1 w - - 0 1',
        solutionMoves: ['d2d8'],
      );

      manager.loadPuzzle(puzzle);
      expect(manager.currentPuzzle?.id, equals('test_puzzle'));
      expect(manager.currentMoveIndex, equals(0));
      expect(manager.isCompleted, isFalse);
      expect(manager.hasFailed, isFalse);
    });

    test('Solving puzzle with correct move', () async {
      const puzzle = ChessPuzzle(
        id: 'back_rank',
        startingFen: '6k1/5ppp/8/8/8/8/3R4/6K1 w - - 0 1',
        solutionMoves: ['d2d8'],
      );

      manager.loadPuzzle(puzzle);

      final success = await manager.playUserMove('d2d8');
      expect(success, isTrue);
      expect(manager.isCompleted, isTrue);
      expect(manager.hasFailed, isFalse);
      expect(mockSpeech.playedTokenSequences.length, equals(1));
      expect(mockSpeech.playedTokenSequences[0], equals(['rook', 'd', '8']));
    });

    test('Failed puzzle attempt', () async {
      const puzzle = ChessPuzzle(
        id: 'back_rank',
        startingFen: '6k1/5ppp/8/8/8/8/3R4/6K1 w - - 0 1',
        solutionMoves: ['d2d8'],
      );

      manager.loadPuzzle(puzzle);

      final success = await manager.playUserMove('d2d4'); // Wrong move
      expect(success, isFalse);
      expect(manager.isCompleted, isFalse);
      expect(manager.hasFailed, isTrue);
      expect(mockSpeech.playedTokenSequences, isEmpty);
    });

    test('Multi-step puzzle with opponent automatic response', () async {
      const puzzle = ChessPuzzle(
        id: 'fork',
        startingFen: 'r3k3/8/8/3N4/8/8/8/6K1 w q - 0 1',
        solutionMoves: ['d5c7', 'e8d7', 'c7a8'],
      );

      manager.loadPuzzle(puzzle);

      // Step 1: User plays Nc7+ (d5c7)
      final step1Success = await manager.playUserMove('d5c7');
      expect(step1Success, isTrue);
      
      // Wait for future delay inside playUserMove for opponent response to execute
      await Future.delayed(const Duration(milliseconds: 1000));

      expect(manager.currentMoveIndex, equals(2)); // user + opponent reply
      expect(manager.isCompleted, isFalse);

      // Verify user move voice and opponent reply voice were played
      expect(mockSpeech.playedTokenSequences.length, equals(2));
      expect(mockSpeech.playedTokenSequences[0], equals(['knight', 'c', '7'])); // Nc7+
      expect(mockSpeech.playedTokenSequences[1], equals(['king', 'd', '7'])); // Kd7 (Opponent reply)

      // Step 2: User plays Nxa8 (c7a8)
      final step2Success = await manager.playUserMove('c7a8');
      expect(step2Success, isTrue);
      expect(manager.isCompleted, isTrue);
      expect(mockSpeech.playedTokenSequences.length, equals(3));
      expect(mockSpeech.playedTokenSequences[2], equals(['knight', 'takes', 'a', '8'])); // Nxa8
    });
  });
}
