import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chess/chess.dart' as ch;

/// Lokales Offline-Tool zur Engine-gestützten Analyse von Anti-Tactics 2.0 Kandidaten.
///
/// Aufruf:
/// dart run tool/analyze_anti_tactics_2_candidates.dart [options]
///
/// Optionen:
///   --input=<pfad>        (Standard: tool/raw_imported_lichess.json)
///   --output=<pfad>       (Standard: tool/review_candidates_v2.json)
///   --engine=<pfad>       (Pfad zur Stockfish-Executable, Standard: stockfish)
///   --limit=<anzahl>      (Standard: 100)
///   --depth=<zahl>        (Rechentiefe, Standard: 15)

void main(List<String> arguments) async {
  String inputPath = 'tool/raw_imported_lichess.json';
  String outputPath = 'tool/review_candidates_v2.json';
  String enginePath = 'stockfish';
  int limit = 100;
  int depth = 15;

  for (final arg in arguments) {
    if (arg.startsWith('--input='))
      inputPath = arg.substring('--input='.length);
    else if (arg.startsWith('--output='))
      outputPath = arg.substring('--output='.length);
    else if (arg.startsWith('--engine='))
      enginePath = arg.substring('--engine='.length);
    else if (arg.startsWith('--limit='))
      limit = int.parse(arg.substring('--limit='.length));
    else if (arg.startsWith('--depth='))
      depth = int.parse(arg.substring('--depth='.length));
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
    final originalFen = puzzle['fen'];

    print('\nAnalysiere [${i + 1}/${puzzles.length}] $id...');

    // 1. Evaluiere die Original-FEN (Ply 1, kurz vor dem eigentlichen Patzer)
    final baseResult = await engine.analyze(originalFen, depth: depth);
    final bestScore = baseResult.bestScore;
    final bestMove = baseResult.bestMove;

    if (bestScore == null || bestMove == null) {
      print('⚠️ Konnte Basis-Analyse für $id nicht durchführen.');
      continue;
    }

    // Ist die Startposition überhaupt einigermaßen ausgeglichen?
    if (bestScore.isMate || bestScore.value.abs() > 150) {
      print(
          '⏭️ Überspringe $id: Startposition ist nicht ausgeglichen (${bestScore.isMate ? 'Mate' : bestScore.value} cp).');
      continue;
    }

    // 2. Wende den besten Zug an, um die Anti-Taktik 2.0 Start-FEN zu generieren (Ply 2)
    final chess = ch.Chess.fromFEN(originalFen);

    // UCI parsen, um ihn mit package:chess auszuführen
    final fromSq = bestMove.substring(0, 2);
    final toSq = bestMove.substring(2, 4);
    String? promoChar;
    if (bestMove.length > 4) {
      promoChar = bestMove.substring(4, 5);
    }

    final moveSuccess =
        chess.move({'from': fromSq, 'to': toSq, 'promotion': promoChar});
    if (!moveSuccess) {
      print('⚠️ Ungültiger Best-Move $bestMove für $id');
      continue;
    }

    final newFen = chess.fen;

    // 3. Evaluiere die neue Position (jetzt ist der Taktik-Spieler dran, aber es gibt keine Taktik!)
    final newResult = await engine.analyze(newFen, depth: depth, multiPv: 2);
    final newBestScore = newResult.bestScore;

    if (newBestScore == null) {
      print('⚠️ Konnte 2. Analyse für $id nicht durchführen.');
      continue;
    }

    if (newBestScore.isMate || newBestScore.value.abs() > 150) {
      print(
          '⏭️ Überspringe $id: Nach Best-Move ist Position nicht ausgeglichen (${newBestScore.isMate ? 'Mate' : newBestScore.value} cp).');
      continue;
    }

    print('✅ Gefunden! Ausgeglichene Anti-Taktik 2.0 für $id erzeugt.');

    final enrichedPuzzle = Map<String, dynamic>.from(puzzle);

    // Überschreibe FEN und erwartete Züge für das V2-Konzept!
    enrichedPuzzle['originalFen'] = originalFen; // Behalten für Reviewer
    enrichedPuzzle['fen'] = newFen;
    enrichedPuzzle['expectedMoves'] =
        []; // Keine spezifische Sequenz, Ziel ist "No Tactic"
    enrichedPuzzle['antiTacticsType'] =
        'noWinningTactic'; // Standard-Typ für V2
    enrichedPuzzle['version'] = 2;

    enrichedPuzzle['analysis'] = {
      'engineBestMoveBefore': bestMove,
      'engineScoreCpBefore': bestScore.value,
      'engineScoreCpAfter': newBestScore.value,
      'reviewReason':
          'Generiert durch V2 Best-Move-Substitution. Start-Eval: ${bestScore.value}, Nach Zug: ${newBestScore.value}',
      'suggestedType': 'noWinningTactic'
    };

    report.add(enrichedPuzzle);
  }

  engine.stop();

  final outputFile = File(outputPath);
  if (!outputFile.parent.existsSync())
    outputFile.parent.createSync(recursive: true);
  await outputFile.writeAsString(JsonEncoder.withIndent('  ').convert(report));

  print(
      '\n✅ Analyse abgeschlossen. ${report.length} Kandidaten unter $outputPath gespeichert.');
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

  Future<AnalysisResult> analyze(String fen, {int? depth, int multiPv = 1}) {
    _analyzeCompleter = Completer<AnalysisResult>();
    _currentBestScore = null;
    _currentSecondScore = null;
    _currentBestMove = null;
    _currentSecondBestMove = null;

    _process!.stdin.writeln('setoption name MultiPV value $multiPv');
    _process!.stdin.writeln('position fen $fen');
    _process!.stdin.writeln('go depth ${depth ?? 15}');

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
