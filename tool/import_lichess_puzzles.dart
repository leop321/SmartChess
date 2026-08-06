import 'dart:convert';
import 'dart:io';

import 'package:chess/chess.dart' as ch;

/// Lokales Offline-Tool zum Importieren von Lichess-Puzzles aus einer CSV-Datei.
///
/// Aufruf:
/// dart run tool/import_lichess_puzzles.dart [options]
///
/// Optionen:
///   --input=<pfad>        (Standard: tool/lichess_db_puzzle.csv)
///   --output=<pfad>       (Standard: tool/raw_imported_lichess.json)
///   --limit=<anzahl>      (Maximal zu importierende Puzzles)
///   --min-rating=<zahl>
///   --max-rating=<zahl>
///   --themes=<theme>      (z. B. "fork,endgame" - Kommaseparierte Lichess-Themes)

void main(List<String> arguments) async {
  String inputPath = 'tool/lichess_db_puzzle.csv';
  String outputPath = 'tool/raw_imported_lichess.json';
  int limit = 100;
  int? minRating;
  int? maxRating;
  List<String> requiredThemes = [];

  // 1. Argumente parsen
  for (final arg in arguments) {
    if (arg.startsWith('--input='))
      inputPath = arg.substring('--input='.length);
    else if (arg.startsWith('--output='))
      outputPath = arg.substring('--output='.length);
    else if (arg.startsWith('--limit='))
      limit = int.parse(arg.substring('--limit='.length));
    else if (arg.startsWith('--min-rating='))
      minRating = int.parse(arg.substring('--min-rating='.length));
    else if (arg.startsWith('--max-rating='))
      maxRating = int.parse(arg.substring('--max-rating='.length));
    else if (arg.startsWith('--themes=')) {
      requiredThemes = arg
          .substring('--themes='.length)
          .split(',')
          .map((e) => e.trim())
          .toList();
    }
  }

  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    print('❌ Eingabedatei existiert nicht: $inputPath');
    print('Bitte lade die Lichess Puzzle CSV herunter und entpacke sie dort.');
    exit(1);
  }

  print('Starte Import von $inputPath (Limit: $limit)...');

  final lines = inputFile
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  final List<Map<String, dynamic>> outputData = [];
  int count = 0;
  bool isFirstLine = true;

  // 2. CSV verarbeiten
  await for (final line in lines) {
    if (isFirstLine) {
      isFirstLine = false;
      continue; // CSV Header überspringen
    }

    final parts = line.split(',');
    if (parts.length < 8) continue;

    final puzzleId = parts[0];
    final rawFen = parts[1];
    final movesStr = parts[2];
    final rating = int.tryParse(parts[3]) ?? 1500;
    final themesRaw = parts[7];

    // Filtern nach Rating
    if (minRating != null && rating < minRating) continue;
    if (maxRating != null && rating > maxRating) continue;

    // Filtern nach Themes
    final lichessThemes = themesRaw.split(' ').map((t) => t.trim()).toList();
    if (requiredThemes.isNotEmpty) {
      bool hasAll = requiredThemes.every((rt) => lichessThemes.contains(rt));
      if (!hasAll) continue;
    }

    // 3. Züge verarbeiten & FEN berechnen
    // Lichess FEN ist die Stellung VOR dem Zug des Gegners.
    // Die Moves-Sequenz startet mit dem Zug des Gegners, dann wir, dann Gegner etc.
    final moves = movesStr.split(' ').map((m) => m.trim()).toList();
    if (moves.length < 2)
      continue; // Wir brauchen mind. Gegnerzug + unseren Zug

    final opponentMove = moves.first;
    final expectedMoves = moves.sublist(1);

    // Wir nutzen chess.dart, um den Gegnerzug auszuführen und die FEN für die Aufgabe zu bekommen
    final chess = ch.Chess.fromFEN(rawFen);
    String from = opponentMove.substring(0, 2);
    String to = opponentMove.substring(2, 4);
    String? promo = opponentMove.length > 4 ? opponentMove[4] : null;

    final moveSuccess =
        chess.move({'from': from, 'to': to, 'promotion': promo});
    if (!moveSuccess) {
      print(
          '⚠️ Warnung: Ungültiger Zug $opponentMove in FEN $rawFen (ID: $puzzleId). Überspringe.');
      continue;
    }

    final puzzleFen = chess.fen;

    // 4. Mapping in unser Schema
    final phase = _mapPhase(lichessThemes);
    final mappedTags = _mapThemes(lichessThemes);

    // Einfache Heuristik für Explanation
    String shortExp = 'Gewinnbringende Taktik gefunden';
    if (mappedTags.contains('fork')) shortExp = 'Gabel / Doppelangriff';
    if (mappedTags.contains('backRank')) shortExp = 'Grundreihen-Motiv';
    if (mappedTags.contains('pin')) shortExp = 'Fesselung ausnutzen';
    if (mappedTags.contains('mateIn1'))
      shortExp = 'Matt in 1';
    else if (mappedTags.contains('mateIn2')) shortExp = 'Matt in 2';

    outputData.add({
      'id': 'lichess_$puzzleId',
      'fen': puzzleFen, // Das ist jetzt die Stellung NACH dem Gegnerzug!
      'mode':
          'antiTactics', // Wir importieren sie bewusst als Anti-Tactics "winningTacticExists" Kandidaten
      'antiTacticsType': 'winningTacticExists',
      'expectedMoves':
          expectedMoves, // Nur noch unsere (und die restlichen) Züge
      'difficulty': rating,
      'tags': mappedTags.toList(),
      'phase': phase,
      'explanationShort': shortExp,
      'explanation':
          'Lichess Puzzle $puzzleId. Finde die beste Zugfolge für ${chess.turn == ch.Color.WHITE ? "Weiß" : "Schwarz"}.'
    });

    count++;
    if (count >= limit) break;
  }

  // 5. Output schreiben
  final outputFile = File(outputPath);
  if (!outputFile.parent.existsSync())
    outputFile.parent.createSync(recursive: true);
  await outputFile
      .writeAsString(JsonEncoder.withIndent('  ').convert(outputData));

  print('✅ Import abgeschlossen. $count Puzzles nach $outputPath exportiert.');
  print(
      'Du kannst nun das tool/build_anti_tactics_dataset.dart drüberlaufen lassen.');
}

/// Leitet die Partiephase grob ab
String? _mapPhase(List<String> lichessThemes) {
  if (lichessThemes.contains('opening')) return 'opening';
  if (lichessThemes.contains('endgame')) return 'endgame';
  if (lichessThemes.contains('middlegame')) return 'middlegame';
  return null;
}

/// Mapped Lichess-Themes auf unser Tag-Vokabular
Set<String> _mapThemes(List<String> lichessThemes) {
  final Set<String> mapped = {};

  for (final t in lichessThemes) {
    switch (t) {
      case 'fork':
        mapped.add('fork');
        break;
      case 'pin':
        mapped.add('pin');
        break;
      case 'skewer':
        mapped.add('skewer');
        break;
      case 'sacrifice':
        mapped.add('sacrifice');
        break;
      case 'deflection':
        mapped.add('deflection');
        break;
      case 'backRankMate':
        mapped.add('backRank');
        mapped.add('mate');
        break;
      case 'mateIn1':
        mapped.add('mateIn1');
        mapped.add('mate');
        break;
      case 'mateIn2':
        mapped.add('mateIn2');
        mapped.add('mate');
        break;
      case 'quietMove':
        mapped.add('quietMove');
        break;
      case 'hangingPiece':
        mapped.add('hangingPiece');
        break;
      case 'discoveredAttack':
        mapped.add('discoveredAttack');
        break;
    }
  }

  // Wenn Lichess sagt, es ist "advantage" und kein Matt, fügen wir einen generischen Tag hinzu
  if (mapped.isEmpty && lichessThemes.contains('advantage')) {
    mapped.add('advantage');
  }

  return mapped;
}
