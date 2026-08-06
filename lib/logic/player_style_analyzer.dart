import 'dart:math';

import '../model/game_analysis_models.dart';

/// Chess player style analysis algorithms.
/// Directly adapted from MoveLab's main.dart:
///   - AccuracyCalculator  (line 533)
///   - PositionAnalyzer    (line 552)
///   - TacticalDetector    (line 600)
///   - AdvancedClassifier  (line 756)
///   - PlayerStyleProfile  (line 1243)
///   - StyleConfig         (line 1261)
///   - StyleNormalizer     (line 1284)
///   - PlayerStyleAnalyzer (line 1320)
///
/// Firebase / language service dependencies removed and replaced with
/// English-only labels.

// ─── Accuracy Calculator ───────────────────────────────────────────────────────

class AccuracyCalculator {
  static const int _mateCentipawn = 1500;

  static double evalToWinPercent(double cp) =>
      50.0 + 50.0 * (2.0 / (1.0 + exp(-0.00368208 * cp)) - 1.0);

  static double cpFromEval(double eval, bool isMate) {
    if (isMate || eval.abs() > 14.0) {
      return eval.isNegative
          ? -_mateCentipawn.toDouble()
          : _mateCentipawn.toDouble();
    }
    return eval * 100.0;
  }

  static double calculateMoveAccuracy(
    double bestEval,
    double playedEval,
    bool isWhiteMove,
    bool isBeforeMate,
    bool isAfterMate,
  ) {
    final cpBest = cpFromEval(bestEval, isBeforeMate);
    final cpPlayed = cpFromEval(playedEval, isAfterMate);
    final bestWin = evalToWinPercent(cpBest);
    final playedWin = evalToWinPercent(cpPlayed);
    final winPercentLoss =
        isWhiteMove ? (bestWin - playedWin) : (playedWin - bestWin);
    if (winPercentLoss <= 0) return 100.0;
    final accuracy = 103.1668 * exp(-0.04354 * winPercentLoss) - 3.1669;
    return accuracy.clamp(0.0, 100.0);
  }
}

// ─── Position Analyzer ────────────────────────────────────────────────────────

class PositionAnalyzer {
  static String getState(double eval) {
    if (eval >= 3.0) return 'winning';
    if (eval >= 1.0) return 'better';
    if (eval > -1.0 && eval < 1.0) return 'equal';
    if (eval <= -1.0 && eval > -3.0) return 'worse';
    return 'losing';
  }

  static double getComplexity(List<double> alternatives) {
    if (alternatives.length < 2) return 0.0;
    final topGap = (alternatives[0] - alternatives[1]).abs();
    double complexity = topGap < 0.5 ? 5.0 : (topGap < 1.5 ? 3.0 : 1.0);
    final nearMoves =
        alternatives.where((e) => (alternatives[0] - e).abs() < 1.0).length;
    complexity += nearMoves * 1.5;
    return complexity.clamp(0.0, 10.0);
  }

  static bool isForced(List<double> alternatives) {
    if (alternatives.length < 2) return true;
    if (alternatives[0] > 3.0 && alternatives[1] > 2.0) return false;
    return (alternatives[0] - alternatives[1]).abs() >= 2.5;
  }
}

// ─── Advanced Move Classifier ─────────────────────────────────────────────────

class AdvancedClassifier {
  static String classifyMove({
    required double bestEval,
    required double playedEval,
    required double accuracy,
    required List<double> alternatives,
    required bool isWhiteMove,
    required bool isMateFound,
    required int sacrificeType,
  }) {
    final evalBefore = isWhiteMove ? bestEval : -bestEval;
    final evalAfter = isWhiteMove ? playedEval : -playedEval;
    final stateBefore = PositionAnalyzer.getState(evalBefore);
    final stateAfter = PositionAnalyzer.getState(evalAfter);
    final complexity = PositionAnalyzer.getComplexity(alternatives);
    final forcedMove = PositionAnalyzer.isForced(alternatives);
    final isMate =
        bestEval.abs() > 14.0 || playedEval.abs() > 14.0 || isMateFound;
    final playerDeliversMate = evalAfter > 14.0;
    final playerReceivesMate = evalAfter < -14.0;
    final evalLoss = (bestEval - playedEval).abs();
    final nearBest = evalLoss <= 0.35 || playerDeliversMate;
    final perfectMove = evalLoss <= 0.15;

    if (sacrificeType >= 3 && nearBest && !playerReceivesMate) {
      return 'Brilliant !!';
    }
    if (!playerReceivesMate &&
        ((sacrificeType == 2 && nearBest) ||
            (sacrificeType == 1 && nearBest && complexity >= 3.0) ||
            (forcedMove && nearBest && !isMate && complexity >= 3.0))) {
      return 'Great !';
    }
    if (stateBefore == 'winning' &&
        (stateAfter == 'equal' ||
            stateAfter == 'losing' ||
            stateAfter == 'worse')) {
      return 'Blunder ??';
    }
    if (stateBefore == 'equal' && stateAfter == 'losing') return 'Blunder ??';
    if (stateBefore == 'better' &&
        (stateAfter == 'worse' || stateAfter == 'losing')) {
      return 'Mistake ?';
    }
    if (playerDeliversMate || perfectMove || accuracy >= 99.0) return 'Best';
    if (accuracy >= 95.0) return 'Excellent';
    if (accuracy >= 88.0) return 'Good';
    if (accuracy >= 75.0) return 'Inaccuracy ?!';
    if (accuracy >= 50.0) return 'Mistake ?';
    return 'Blunder ??';
  }

  static bool isBrilliant(String label) => label.startsWith('Brilliant');
  static bool isGreat(String label) => label.startsWith('Great');
}

// ─── Style Config ─────────────────────────────────────────────────────────────

class _StyleConfig {
  static const double aggActionWeight = 0.35;
  static const double aggSpeedWeight = 0.25;
  static const double aggShortWinWeight = 0.25;
  static const double aggGambitWeight = 0.15;

  static const double defEndgameWeight = 0.40;
  static const double defPassiveWeight = 0.30;
  static const double defAccWeight = 0.30;

  static const double tacActionWeight = 0.30;
  static const double tacAccWeight = 0.40;
  static const double tacShortWinWeight = 0.30;

  static const double posEndgameWeight = 0.35;
  static const double posAccWeight = 0.45;
  static const double posPassiveWeight = 0.20;

  static const double rskChaosWeight = 0.40;
  static const double rskGambitWeight = 0.30;
  static const double rskShortWinWeight = 0.30;
}

// ─── Style Normalizer ─────────────────────────────────────────────────────────

class _StyleNormalizer {
  static int scale(
    double val,
    double minRaw,
    double maxRaw,
    double minOut,
    double maxOut,
    int rating,
  ) {
    double ratio = ((val - minRaw) / (maxRaw - minRaw)).clamp(0.0, 1.0);
    double dynamicFloor = ((rating / 2500.0) * 55.0).clamp(10.0, 60.0);
    double potentialCeiling =
        ((rating / 2500.0) * 100.0 + 20.0).clamp(40.0, 99.0);
    double boost =
        ratio > 0.5 ? (ratio - 0.5) * 2.0 * (rating / 2500.0) * 25.0 : 0.0;
    double baseScore =
        dynamicFloor + (ratio * (potentialCeiling - dynamicFloor));
    return (baseScore + boost).clamp(dynamicFloor, 99.0).toInt();
  }
}

// ─── Player Style Analyzer ────────────────────────────────────────────────────

class PlayerStyleAnalyzer {
  /// Analyses a list of [GameEntry] objects for [username] with [rating].
  /// Adapted from MoveLab's PlayerStyleAnalyzer.analyze (line 1321).
  static PlayerStyleProfile analyze(
    String username,
    List<GameEntry> games,
    int rating,
  ) {
    if (games.isEmpty) return PlayerStyleProfile.neutral();

    int shortWins = 0, longGames = 0, gambits = 0, positionalOpenings = 0;
    double totalAccuracy = 0;
    int gamesWithAcc = 0;
    int totalChecks = 0, totalCaptures = 0, totalMoves = 0, wins = 0;

    for (final g in games) {
      final isWhite = g.white.toLowerCase() == username.toLowerCase();
      final isWin = g.winner == (isWhite ? 'white' : 'black');
      if (isWin) wins++;

      final fullText = '${g.pgn} ${g.moves}'.toLowerCase();

      if (fullText.contains('gambit') ||
          fullText.contains('sicilian') ||
          fullText.contains('dutch') ||
          fullText.contains('vienna') ||
          fullText.contains('benoni') ||
          fullText.contains('evans') ||
          fullText.contains('morra')) gambits++;

      if (fullText.contains("queen's gambit") ||
          fullText.contains('english') ||
          fullText.contains('catalan') ||
          fullText.contains('reti') ||
          fullText.contains('nimzo') ||
          fullText.contains('bogo') ||
          fullText.contains('pianissimo')) positionalOpenings++;

      int moveCount = 30;
      if (g.moves.isNotEmpty) {
        moveCount = (g.moves.trim().split(RegExp(r'\s+')).length / 2).ceil();
      } else if (g.pgn.isNotEmpty) {
        final m = RegExp(r'\d+\.').allMatches(g.pgn);
        if (m.isNotEmpty) moveCount = m.length;
      }
      if (moveCount < 5) moveCount = 5;
      totalMoves += moveCount;
      if (isWin && moveCount <= 25) shortWins++;
      if (moveCount >= 50) longGames++;

      totalChecks += RegExp(r'\+').allMatches(fullText).length;
      totalCaptures += RegExp(r'x').allMatches(fullText).length;

      double acc =
          isWhite ? (g.whiteAccuracy ?? 0.0) : (g.blackAccuracy ?? 0.0);
      if (acc > 0) {
        totalAccuracy += acc;
        gamesWithAcc++;
      } else {
        double guessedAcc = 75.0 + (min(20, (50 - moveCount).abs()) * 0.4);
        totalAccuracy +=
            isWin ? min(99.0, guessedAcc + 5.0) : max(40.0, guessedAcc - 10.0);
        gamesWithAcc++;
      }
    }

    final gc = games.length;
    final avgAcc = gamesWithAcc > 0 ? totalAccuracy / gamesWithAcc : 50.0;
    final avgMoves = totalMoves / gc;

    final rawAction = (totalCaptures + totalChecks * 1.5) / totalMoves;
    final fAction = min(1.0, rawAction / 0.6);
    final fSpeed = max(0.0, min(1.0, (60.0 - avgMoves) / 40.0));
    final fShortWin = shortWins / gc;
    final fGambit = min(1.0, (gambits / gc) * 2.0);
    final fAcc = avgAcc / 100.0;
    final fEndgame = longGames / gc;
    final fWin = wins / gc;
    final fChaos = min(1.0, (1.0 - fAcc) * fAction * 2.5);

    final aggScore = fAction * _StyleConfig.aggActionWeight +
        fSpeed * _StyleConfig.aggSpeedWeight +
        fShortWin * _StyleConfig.aggShortWinWeight +
        fGambit * _StyleConfig.aggGambitWeight;
    final defScore = fEndgame * _StyleConfig.defEndgameWeight +
        (1.0 - fAction) * _StyleConfig.defPassiveWeight +
        fAcc * _StyleConfig.defAccWeight;
    final tacScore = fAction * _StyleConfig.tacActionWeight +
        fAcc * _StyleConfig.tacAccWeight +
        fShortWin * _StyleConfig.tacShortWinWeight;
    final posScore = fEndgame * _StyleConfig.posEndgameWeight +
        fAcc * _StyleConfig.posAccWeight +
        (1.0 - fAction) * _StyleConfig.posPassiveWeight;
    final rskScore = fChaos * _StyleConfig.rskChaosWeight +
        fGambit * _StyleConfig.rskGambitWeight +
        fShortWin * _StyleConfig.rskShortWinWeight;
    final fPosOpening = positionalOpenings / gc;
    final opnScore =
        fAcc > 0.75 ? fAcc * 0.5 + fWin * 0.3 + fPosOpening * 0.2 : fAcc * 0.4;

    return _determineStyles(PlayerStyleProfile(
      aggressive: _StyleNormalizer.scale(aggScore, 0.20, 0.75, 25, 99, rating),
      defensive: _StyleNormalizer.scale(defScore, 0.30, 0.85, 20, 99, rating),
      tactical: _StyleNormalizer.scale(tacScore, 0.30, 0.80, 30, 99, rating),
      positional: _StyleNormalizer.scale(posScore, 0.35, 0.85, 30, 99, rating),
      opening: _StyleNormalizer.scale(opnScore, 0.40, 0.90, 15, 99, rating),
      risk: _StyleNormalizer.scale(rskScore, 0.10, 0.65, 15, 99, rating),
      mainStyle: '',
      mainIcon: '',
      subStyles: const [],
    ));
  }

  static PlayerStyleProfile _determineStyles(PlayerStyleProfile p) {
    final scores = <String, int>{
      '🔥 Aggressive': p.aggressive,
      '🛡️ Defensive': p.defensive,
      '⚔️ Tactical': p.tactical,
      '🧠 Positional': p.positional,
      '🎯 Opening Expert': p.opening,
      '🎲 Risk Taker': p.risk,
    };

    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final main = sorted[0].key;
    final icon = main.split(' ')[0];
    final styleName = main.substring(main.indexOf(' ') + 1);
    final subs = [sorted[1].key, sorted[2].key];

    return PlayerStyleProfile(
      aggressive: p.aggressive,
      defensive: p.defensive,
      tactical: p.tactical,
      positional: p.positional,
      opening: p.opening,
      risk: p.risk,
      mainStyle: styleName,
      mainIcon: icon,
      subStyles: subs,
    );
  }
}
