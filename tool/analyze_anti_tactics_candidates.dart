import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chess/chess.dart' as ch;

/// Lokales Offline-Tool zur Engine-gestützten Analyse von Anti-Tactics-Kandidaten,
/// inklusive gezielter Candidate-Move-Analyse für "Deceptive No-Tactics".
///
/// Aufruf:
/// dart run tool/analyze_anti_tactics_candidates.dart [options]
///
/// Optionen:
///   --input=<pfad>        (Standard: tool/raw_imported_lichess.json)
///   --output=<pfad>       (Standard: tool/analysis_report.json)
///   --engine=<pfad>       (Pfad zur Stockfish-Executable, Standard: stockfish)
///   --limit=<anzahl>
///   --candidate-limit=<n> (Maximal zu prüfende Kandidatenzüge, Standard: 5)
///   --depth=<zahl>        (Rechentiefe, Standard: 16)
///   --movetime=<ms>       (Alternativ: max. Zeit pro Zug in ms)

void main(List<String> arguments) async {
  String inputPath = 'tool/raw_imported_lichess.json';
  String outputPath = 'tool/analysis_report.json';
  String enginePath = 'stockfish';
  int limit = 100;
  int candidateLimit = 5;
  int? depth = 16;
  int? movetime;

  for (final arg in arguments) {
    if (arg.startsWith('--input='))
      inputPath = arg.substring('--input='.length);
    else if (arg.startsWith('--output='))
      outputPath = arg.substring('--output='.length);
    else if (arg.startsWith('--engine='))
      enginePath = arg.substring('--engine='.length);
    else if (arg.startsWith('--limit='))
      limit = int.parse(arg.substring('--limit='.length));
    else if (arg.startsWith('--candidate-limit='))
      candidateLimit = int.parse(arg.substring('--candidate-limit='.length));
    else if (arg.startsWith('--depth=')) {
      depth = int.parse(arg.substring('--depth='.length));
      movetime = null;
    } else if (arg.startsWith('--movetime=')) {
      movetime = int.parse(arg.substring('--movetime='.length));
      depth = null;
    }
  }

  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    print('❌ Eingabedatei existiert nicht: $inputPath');
    exit(1);
  }

  print('Lade Puzzles aus $inputPath...');
  final List<dynamic> rawData = jsonDecode(await inputFile.readAsString());
  final puzzles = rawData.take(limit).cast<Map<String, dynamic>>().toList();

  print('Starte Stockfish: $enginePath');
  final engine = UciEngine(enginePath);
  try {
    await engine.start();
  } catch (e) {
    print(
        '❌ Fehler beim Starten von Stockfish. Ist der Pfad korrekt? ($enginePath)');
    exit(1);
  }

  await engine.sendInitCommands();

  final List<Map<String, dynamic>> report = [];

  for (int i = 0; i < puzzles.length; i++) {
    final puzzle = puzzles[i];
    final id = puzzle['id'];
    final fen = puzzle['fen'];
    final type = puzzle['antiTacticsType'];
    final expectedMoves = List<String>.from(puzzle['expectedMoves'] ?? []);
    final expectedFirstMove =
        expectedMoves.isNotEmpty ? expectedMoves.first : '';

    print('\nAnalysiere [${i + 1}/${puzzles.length}] $id...');

    // 1. Basis-Analyse (Top 2 Züge)
    final baseResult =
        await engine.analyze(fen, depth: depth, movetime: movetime, multiPv: 2);
    final bestScore = baseResult.bestScore;
    final secondScore = baseResult.secondScore;
    final bestMove = baseResult.bestMove;

    if (bestScore == null || bestMove == null) {
      print('⚠️ Konnte Basis-Analyse für $id nicht durchführen.');
      continue;
    }

    // 2. Kandidaten heuristisch ermitteln (Schach, Schlagen, Promotion, Expected)
    final chess = ch.Chess.fromFEN(fen);
    final allMoves =
        chess.moves({'verbose': true}).cast<Map<String, dynamic>>();

    final List<Map<String, dynamic>> forcingCandidates = [];
    bool isBestMoveQuiet = true;

    for (final vm in allMoves) {
      final String uci = vm['from'] + vm['to'] + (vm['promotion'] ?? '');
      final bool isCheck = vm['san'].toString().contains('+') ||
          vm['san'].toString().contains('#');
      final bool isCapture = vm['flags'].toString().contains('c') ||
          vm['flags'].toString().contains('e');
      final bool isPromotion = vm['flags'].toString().contains('p');
      final bool isExpected = (uci == expectedFirstMove);

      if (uci == bestMove && (isCheck || isCapture || isPromotion)) {
        isBestMoveQuiet = false;
      }

      if (isCheck || isCapture || isPromotion || isExpected) {
        forcingCandidates.add({
          'uci': uci,
          'isCheck': isCheck,
          'isCapture': isCapture,
          'isPromotion': isPromotion,
          'isExpected': isExpected,
        });
      }
    }

    // Sortiere nach Priorität (Checks > Captures > Promotions), limitiere dann
    forcingCandidates.sort((a, b) {
      if (a['isExpected'] && !b['isExpected']) return -1;
      if (!a['isExpected'] && b['isExpected']) return 1;
      if (a['isCheck'] && !b['isCheck']) return -1;
      if (!a['isCheck'] && b['isCheck']) return 1;
      if (a['isCapture'] && !b['isCapture']) return -1;
      if (!a['isCapture'] && b['isCapture']) return 1;
      return 0;
    });

    final candidatesToAnalyze = forcingCandidates.take(candidateLimit).toList();
    final List<Map<String, dynamic>> candidateAnalyses = [];

    bool deceptiveCandidateFound = false;
    String deceptiveCandidateMove = '';
    const int deceptiveDeltaCp =
        150; // Wenn ein verlockender Zug > 1.5 Bauern schlechter ist

    // 3. Gezielte Candidate-Analyse via searchmoves
    for (final cand in candidatesToAnalyze) {
      final candUci = cand['uci'] as String;

      // Überspringe den global besten Zug, da wir dessen Score schon kennen (spart Zeit)
      Score? candScore;
      if (candUci == bestMove) {
        candScore = bestScore;
      } else if (candUci == baseResult.secondBestMove && secondScore != null) {
        candScore = secondScore;
      } else {
        final candResult = await engine.analyze(fen,
            depth: depth, movetime: movetime, searchmoves: candUci);
        candScore = candResult.bestScore;
      }

      if (candScore != null) {
        int delta = 0;
        if (!bestScore.isMate && !candScore.isMate) {
          delta = bestScore.value -
              candScore.value; // Delta ist positiv, wenn cand schlechter ist
        } else if (bestScore.isMate && !candScore.isMate) {
          delta = 9999; // Matt verpasst
        } else if (!bestScore.isMate &&
            candScore.isMate &&
            candScore.value < 0) {
          delta = 9999; // Blunder in ein Matt
        }

        // Kategorie-Label für den Report
        String cat = 'other';
        if (cand['isExpected'])
          cat = 'expected';
        else if (cand['isCheck'])
          cat = 'check';
        else if (cand['isCapture'])
          cat = 'capture';
        else if (cand['isPromotion']) cat = 'promotion';

        candidateAnalyses.add({
          'move': candUci,
          'scoreCp': candScore.isMate ? null : candScore.value,
          'scoreMate': candScore.isMate ? candScore.value : null,
          'deltaFromBest': delta,
          'category': cat,
        });

        // Ist das ein fieser "Deceptive" Zug?
        // Er ist verlockend (weil Check/Capture), aber führt zu schlechterem Ergebnis!
        if (delta >= deceptiveDeltaCp &&
            (cand['isCheck'] || cand['isCapture'])) {
          deceptiveCandidateFound = true;
          if (deceptiveCandidateMove.isEmpty) deceptiveCandidateMove = candUci;
        }
      }
    }

    // 4. Neue Heuristik
    const int clearWinGapCp = 150;
    const int noWinMaxGapCp = 50;

    int gap = 0;
    if (!bestScore.isMate && secondScore != null && !secondScore.isMate) {
      gap = bestScore.value - secondScore.value;
    } else if (bestScore.isMate ||
        (secondScore != null && secondScore.isMate)) {
      gap = 9999;
    }

    String suggestedType = 'reviewNeeded';
    String reviewReason = '';

    if (gap >= clearWinGapCp || bestScore.isMate) {
      suggestedType = 'winningTacticExists';
      reviewReason = 'Klare Taktik / Forcierender Gewinn vorhanden';
    } else if (gap <= noWinMaxGapCp && !bestScore.isMate) {
      if (deceptiveCandidateFound) {
        suggestedType = 'deceptiveNoTactic';
        reviewReason =
            'Top-Züge unklar, ABER es gibt einen falschen verlockenden Zug ($deceptiveCandidateMove)';
      } else {
        suggestedType = 'noWinningTactic';
        reviewReason =
            'Keine klare Taktik, Top-Züge sehr ähnlich, keine verlockenden Blunder';
      }
    } else {
      reviewReason = 'Lücke zwischen Zügen unklar ($gap cp)';
    }

    // Abgleich mit bisherigem Label
    if (suggestedType == type) {
      reviewReason = 'Engine bestätigt Label ($reviewReason)';
    } else if (type == 'noWinningTactic' &&
        suggestedType == 'deceptiveNoTactic') {
      reviewReason = 'Aufwertung zu deceptiveNoTactic!';
    } else if (type != null && type != 'antiTactics') {
      reviewReason = 'Widerspruch: Ist $type, Engine sagt $suggestedType';
    }

    final enrichedPuzzle = Map<String, dynamic>.from(puzzle);
    enrichedPuzzle['analysis'] = {
      'engineBestMove': bestMove,
      'engineScoreCp': bestScore.isMate ? null : bestScore.value,
      'engineScoreMate': bestScore.isMate ? bestScore.value : null,
      'secondBestScoreCp':
          secondScore?.isMate == true ? null : secondScore?.value,
      'scoreGap': gap,
      'quietBestMove': isBestMoveQuiet,
      'deceptiveCandidateFound': deceptiveCandidateFound,
      'deceptiveCandidateMove':
          deceptiveCandidateFound ? deceptiveCandidateMove : null,
      'expectedMatchesEngine': bestMove == expectedFirstMove,
      'suggestedType': suggestedType,
      'reviewReason': reviewReason,
      'candidateMovesAnalyzed': candidateAnalyses.length,
      'candidateAnalyses': candidateAnalyses,
    };

    report.add(enrichedPuzzle);
  }

  engine.stop();

  final outputFile = File(outputPath);
  if (!outputFile.parent.existsSync())
    outputFile.parent.createSync(recursive: true);
  await outputFile.writeAsString(JsonEncoder.withIndent('  ').convert(report));

  print('\n✅ Analyse abgeschlossen. Report unter $outputPath gespeichert.');
}

class Score {
  final int value;
  final bool isMate;
  Score(this.value, this.isMate);
}

class AnalysisResult {
  final String? bestMove;
  final String? secondBestMove;
  final Score? bestScore;
  final Score? secondScore;

  AnalysisResult(
      {this.bestMove, this.secondBestMove, this.bestScore, this.secondScore});
}

class UciEngine {
  final String executable;
  Process? _process;
  Completer<AnalysisResult>? _analyzeCompleter;

  Score? _currentBestScore;
  Score? _currentSecondScore;
  String? _currentBestMove;
  String? _currentSecondBestMove;

  UciEngine(this.executable);

  Future<void> start() async {
    _process = await Process.start(executable, []);
    _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine);
  }

  Future<void> sendInitCommands() async {
    _process!.stdin.writeln('uci');
    _process!.stdin.writeln('isready');
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<AnalysisResult> analyze(String fen,
      {int? depth, int? movetime, int multiPv = 1, String? searchmoves}) {
    _analyzeCompleter = Completer<AnalysisResult>();
    _currentBestScore = null;
    _currentSecondScore = null;
    _currentBestMove = null;
    _currentSecondBestMove = null;

    _process!.stdin.writeln('setoption name MultiPV value $multiPv');
    _process!.stdin.writeln('position fen $fen');

    String goCommand = '';
    if (depth != null)
      goCommand += ' depth $depth';
    else if (movetime != null)
      goCommand += ' movetime $movetime';
    else
      goCommand += ' depth 16';

    if (searchmoves != null) goCommand += ' searchmoves $searchmoves';

    _process!.stdin.writeln('go$goCommand');

    return _analyzeCompleter!.future;
  }

  void _onLine(String line) {
    if (line.startsWith('info ')) {
      if (line.contains('score mate') || line.contains('score cp')) {
        int multipv = 1;
        final mpvMatch = RegExp(r'multipv (\d+)').firstMatch(line);
        if (mpvMatch != null) multipv = int.parse(mpvMatch.group(1)!);

        bool isMate = false;
        int scoreVal = 0;
        final cpMatch = RegExp(r'score cp (-?\d+)').firstMatch(line);
        if (cpMatch != null) {
          scoreVal = int.parse(cpMatch.group(1)!);
        } else {
          final mateMatch = RegExp(r'score mate (-?\d+)').firstMatch(line);
          if (mateMatch != null) {
            isMate = true;
            scoreVal = int.parse(mateMatch.group(1)!);
          }
        }

        final scoreObj = Score(scoreVal, isMate);

        // Versuche auch den Zug (pv) auszulesen
        String? pvMove;
        final pvMatch =
            RegExp(r' pv ([a-h][1-8][a-h][1-8][qrbn]?)').firstMatch(line);
        if (pvMatch != null) pvMove = pvMatch.group(1);

        if (multipv == 1) {
          _currentBestScore = scoreObj;
          if (pvMove != null) _currentBestMove = pvMove;
        } else if (multipv == 2) {
          _currentSecondScore = scoreObj;
          if (pvMove != null) _currentSecondBestMove = pvMove;
        }
      }
    } else if (line.startsWith('bestmove ')) {
      final parts = line.split(' ');
      if (parts.length >= 2) _currentBestMove = parts[1];

      if (_analyzeCompleter != null && !_analyzeCompleter!.isCompleted) {
        _analyzeCompleter!.complete(AnalysisResult(
          bestMove: _currentBestMove,
          secondBestMove: _currentSecondBestMove,
          bestScore: _currentBestScore,
          secondScore: _currentSecondScore,
        ));
      }
    }
  }

  void stop() {
    _process?.stdin.writeln('quit');
    _process?.kill();
  }
}
