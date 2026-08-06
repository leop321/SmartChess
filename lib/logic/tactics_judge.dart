import '../model/tactics_task.dart';

enum JudgeVerdict { correct, wrong, solved, ignore }

class JudgeResult {
  final JudgeVerdict verdict;
  final String? feedback;

  const JudgeResult(this.verdict, {this.feedback});
}

abstract class TacticsJudge {
  JudgeResult evaluateMove(TacticsTask task, int moveIndex, String uciMove);
  JudgeResult evaluateAction(TacticsTask task, TacticsAction action);
}

class ClassicTacticsJudge implements TacticsJudge {
  @override
  JudgeResult evaluateMove(TacticsTask task, int moveIndex, String uciMove) {
    if (moveIndex >= task.expectedMoves.length) {
      return const JudgeResult(JudgeVerdict.ignore);
    }

    if (task.expectedMoves[moveIndex] == uciMove) {
      if (moveIndex == task.expectedMoves.length - 1) {
        return const JudgeResult(JudgeVerdict.solved);
      }
      return const JudgeResult(JudgeVerdict.correct);
    }
    return const JudgeResult(JudgeVerdict.wrong);
  }

  @override
  JudgeResult evaluateAction(TacticsTask task, TacticsAction action) {
    return const JudgeResult(JudgeVerdict.ignore);
  }
}

class AntiTacticsJudge implements TacticsJudge {
  @override
  JudgeResult evaluateMove(TacticsTask task, int moveIndex, String uciMove) {
    if (task.antiTacticsType == AntiTacticsType.noWinningTactic) {
      return const JudgeResult(
        JudgeVerdict.wrong,
        feedback: "Hier gab es keinen klaren taktischen Gewinnzug.",
      );
    }

    if (moveIndex >= task.expectedMoves.length) {
      return const JudgeResult(JudgeVerdict.ignore);
    }

    if (task.expectedMoves[moveIndex] == uciMove) {
      if (moveIndex == task.expectedMoves.length - 1) {
        return const JudgeResult(JudgeVerdict.solved);
      }
      return const JudgeResult(JudgeVerdict.correct);
    }
    return const JudgeResult(JudgeVerdict.wrong);
  }

  @override
  JudgeResult evaluateAction(TacticsTask task, TacticsAction action) {
    if (action == TacticsAction.declareNoTactic) {
      if (task.antiTacticsType == AntiTacticsType.noWinningTactic) {
        return const JudgeResult(JudgeVerdict.solved);
      }
      return const JudgeResult(
        JudgeVerdict.wrong,
        feedback: "Doch, es gab einen Gewinnzug!",
      );
    }
    return const JudgeResult(JudgeVerdict.ignore);
  }
}
