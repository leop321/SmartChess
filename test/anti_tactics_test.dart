import 'package:en_passant/logic/puzzle_providers/tactics_task_provider.dart';
import 'package:en_passant/logic/tactics_judge.dart';
import 'package:en_passant/logic/tactics_puzzle_controller.dart';
import 'package:en_passant/model/app_model.dart';
import 'package:en_passant/model/lichess_puzzle.dart';
import 'package:en_passant/model/tactics_task.dart';
import 'package:en_passant/model/user_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeProvider implements TacticsTaskProvider {
  final TacticsTask taskToReturn;
  FakeProvider(this.taskToReturn);

  @override
  Future<TacticsTask> fetchNextTask() async => taskToReturn;

  @override
  Future<TacticsTask> fetchTaskById(String id) async => taskToReturn;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('1. Judge-Tests', () {
    final classicJudge = ClassicTacticsJudge();
    final antiJudge = AntiTacticsJudge();

    final classicTask = const TacticsTask(
      id: '1',
      fen: '8/8/8/8/8/8/8/8 w - - 0 1',
      mode: TacticsMode.classic,
      expectedMoves: ['e2e4', 'e7e5'],
      difficulty: 1000,
    );

    final winningTask = const TacticsTask(
      id: '2',
      fen: '8/8/8/8/8/8/8/8 w - - 0 1',
      mode: TacticsMode.antiTactics,
      antiTacticsType: AntiTacticsType.winningTacticExists,
      expectedMoves: ['a1a8'],
      difficulty: 1000,
    );

    final noWinningTask = const TacticsTask(
      id: '3',
      fen: '8/8/8/8/8/8/8/8 w - - 0 1',
      mode: TacticsMode.antiTactics,
      antiTacticsType: AntiTacticsType.noWinningTactic,
      expectedMoves: [],
      difficulty: 1000,
    );

    test('ClassicTacticsJudge', () {
      // korrekter Zug => correct
      expect(classicJudge.evaluateMove(classicTask, 0, 'e2e4').verdict,
          JudgeVerdict.correct);
      // korrekter Zug (letzter) => solved
      expect(classicJudge.evaluateMove(classicTask, 1, 'e7e5').verdict,
          JudgeVerdict.solved);
      // falscher Zug => wrong
      expect(classicJudge.evaluateMove(classicTask, 0, 'd2d4').verdict,
          JudgeVerdict.wrong);
      // Action in Classic => ignore
      expect(
          classicJudge
              .evaluateAction(classicTask, TacticsAction.declareNoTactic)
              .verdict,
          JudgeVerdict.ignore);
    });

    test('AntiTacticsJudge', () {
      // korrekter Taktikzug bei winningTacticExists => solved
      expect(antiJudge.evaluateMove(winningTask, 0, 'a1a8').verdict,
          JudgeVerdict.solved);
      // declareNoTactic bei winningTacticExists => wrong
      expect(
          antiJudge
              .evaluateAction(winningTask, TacticsAction.declareNoTactic)
              .verdict,
          JudgeVerdict.wrong);

      // declareNoTactic bei noWinningTactic => solved
      expect(
          antiJudge
              .evaluateAction(noWinningTask, TacticsAction.declareNoTactic)
              .verdict,
          JudgeVerdict.solved);
      // normaler Zug bei noWinningTactic => wrong
      expect(antiJudge.evaluateMove(noWinningTask, 0, 'a1a8').verdict,
          JudgeVerdict.wrong);
    });
  });

  group('2. JSON und Provider-Tests', () {
    test('TacticsTask.fromJson parst korrekte Daten', () {
      final jsonMap = {
        "id": "test_id",
        "fen": "8/8/8/8/8/8/8/8 w - - 0 1",
        "mode": "antiTactics",
        "antiTacticsType": "winningTacticExists",
        "expectedMoves": ["e2e4"],
        "difficulty": 1200,
        "explanation": "Test",
      };

      final task = TacticsTask.fromJson(jsonMap);

      expect(task.id, 'test_id');
      expect(task.mode, TacticsMode.antiTactics);
      expect(task.antiTacticsType, AntiTacticsType.winningTacticExists);
      expect(task.expectedMoves.first, 'e2e4');
      expect(task.difficulty, 1200);
      expect(task.explanation, 'Test');
    });

    test('TacticsTask.fromJson parst noWinningTactic', () {
      final jsonMap = {
        "id": "test_id_2",
        "fen": "8/8/8/8/8/8/8/8 w - - 0 1",
        "mode": "antiTactics",
        "antiTacticsType": "noWinningTactic",
        "expectedMoves": [],
        "difficulty": 1000,
      };

      final task = TacticsTask.fromJson(jsonMap);

      expect(task.mode, TacticsMode.antiTactics);
      expect(task.antiTacticsType, AntiTacticsType.noWinningTactic);
      expect(task.expectedMoves, isEmpty);
      expect(task.explanation, isNull);
    });
  });

  group('3. Storage-Tests', () {
    test('Rating classic und antiTactics getrennt', () async {
      await TacticsStorage.saveRating(1500, mode: TacticsMode.classic.name);
      await TacticsStorage.saveRating(1800, mode: TacticsMode.antiTactics.name);

      final cRating =
          await TacticsStorage.loadRating(mode: TacticsMode.classic.name);
      final aRating =
          await TacticsStorage.loadRating(mode: TacticsMode.antiTactics.name);

      expect(cRating, 1500);
      expect(aRating, 1800);
    });

    test('History classic und antiTactics getrennt', () async {
      final rec1 = PuzzleRecord(
          puzzleId: 'C1', ratingChange: 10, solved: true, elapsedSeconds: 5);
      final rec2 = PuzzleRecord(
          puzzleId: 'A1', ratingChange: -5, solved: false, elapsedSeconds: 20);

      await TacticsStorage.saveHistory([rec1], mode: TacticsMode.classic.name);
      await TacticsStorage.saveHistory([rec2],
          mode: TacticsMode.antiTactics.name);

      final cHist =
          await TacticsStorage.loadHistory(mode: TacticsMode.classic.name);
      final aHist =
          await TacticsStorage.loadHistory(mode: TacticsMode.antiTactics.name);

      expect(cHist.length, 1);
      expect(cHist.first.puzzleId, 'C1');
      expect(aHist.length, 1);
      expect(aHist.first.puzzleId, 'A1');
    });
  });

  group('4. Controller-nahe Tests', () {
    test('Controller handleAction(declareNoTactic)', () async {
      final prefs = UserPreferences();
      await prefs.load();
      final appModel = AppModel(prefs: prefs);

      final noWinningTask = const TacticsTask(
        id: 'mock',
        fen: '6k1/5ppp/8/8/8/8/5PPP/6K1 w - - 0 1',
        mode: TacticsMode.antiTactics,
        antiTacticsType: AntiTacticsType.noWinningTactic,
        expectedMoves: [],
        difficulty: 1000,
      );

      final fakeProvider = FakeProvider(noWinningTask);
      final judge = AntiTacticsJudge();

      final controller = TacticsPuzzleController(
        appModel,
        mode: TacticsMode.antiTactics,
        provider: fakeProvider,
        judge: judge,
      );

      // Warte auf _loadPersistedData & fetchNextPuzzle
      await Future.delayed(const Duration(milliseconds: 500));

      expect(controller.status, PuzzleStatus.idle);

      // Aktion auslösen -> solved (Da noWinningTactic)
      controller.handleAction(TacticsAction.declareNoTactic);

      expect(controller.status, PuzzleStatus.solved);
      controller.dispose();
    });
  });
}
