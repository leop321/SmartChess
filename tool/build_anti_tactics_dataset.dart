import 'dart:convert';
import 'dart:io';

/// Ein lokales Offline-Tool zur Validierung, Normalisierung und Konvertierung
/// von rohen Anti-Tactics-Datensätzen in das finale App-kompatible JSON-Schema.
///
/// Aufruf:
/// dart run tool/build_anti_tactics_dataset.dart [options]
///
/// Optionen:
///   --input=<pfad>   (Standard: tool/raw_anti_tactics.json)
///   --output=<pfad>  (Standard: assets/data/anti_tactics_tasks.json)
///   --check          (Nur validieren, keine Ausgabe schreiben)
///   --lenient        (Fehlerhafte Einträge überspringen statt abzubrechen)

void main(List<String> arguments) async {
  String inputPath = 'tool/raw_anti_tactics.json';
  String outputPath = 'assets/data/anti_tactics_tasks.json';
  bool checkOnly = false;
  bool lenient = false;

  for (final arg in arguments) {
    if (arg.startsWith('--input=')) {
      inputPath = arg.substring('--input='.length);
    } else if (arg.startsWith('--output=')) {
      outputPath = arg.substring('--output='.length);
    } else if (arg == '--check') {
      checkOnly = true;
    } else if (arg == '--lenient') {
      lenient = true;
    }
  }

  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    print('❌ Fehler: Eingabedatei existiert nicht: $inputPath');
    exit(1);
  }

  print('Lese Rohdaten aus: $inputPath');
  final rawContent = await inputFile.readAsString();
  List<dynamic> rawList;
  try {
    rawList = jsonDecode(rawContent) as List<dynamic>;
  } catch (e) {
    print('❌ Fehler: Datei ist kein gültiges JSON.');
    exit(1);
  }

  final Set<String> seenIds = {};
  final List<Map<String, dynamic>> validTasks = [];
  int errorCount = 0;

  // Stats
  int countWinning = 0;
  int countNoWinning = 0;
  final Map<String, int> phaseDist = {};
  final Map<String, int> tagDist = {};

  for (int i = 0; i < rawList.length; i++) {
    final entry = rawList[i];
    if (entry is! Map<String, dynamic>) {
      _reportError(i, null, 'Eintrag ist kein JSON-Objekt.', lenient);
      errorCount++;
      continue;
    }

    try {
      final validTask = _processAndValidateEntry(entry, seenIds);
      validTasks.add(validTask);

      // Collect Stats
      if (validTask['antiTacticsType'] == 'winningTacticExists') {
        countWinning++;
      } else {
        countNoWinning++;
      }

      final phase = validTask['phase'] as String?;
      if (phase != null && phase.isNotEmpty) {
        phaseDist[phase] = (phaseDist[phase] ?? 0) + 1;
      }

      final tags = validTask['tags'] as List<dynamic>;
      for (final tag in tags) {
        tagDist[tag.toString()] = (tagDist[tag.toString()] ?? 0) + 1;
      }
    } catch (e) {
      _reportError(i, entry['id']?.toString(), e.toString(), lenient);
      errorCount++;
      if (!lenient) {
        print('Abbruch aufgrund von strict-Modus.');
        exit(1);
      }
    }
  }

  print('\n=== Zusammenfassung ===');
  print('Geprüfte Einträge: ${rawList.length}');
  print('Gültige Einträge:  ${validTasks.length}');
  print('Fehlerhafte:       $errorCount');
  print('-----------------------');
  print('winningTacticExists: $countWinning');
  print('noWinningTactic:     $countNoWinning');
  print('Phasen-Verteilung:   $phaseDist');

  final sortedTags = tagDist.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  print(
      'Top 5 Tags:          ${sortedTags.take(5).map((e) => "${e.key}(${e.value})").join(', ')}');

  if (errorCount > 0 && !lenient) {
    print('\n❌ Fehlerhafte Einträge gefunden. Abbruch ohne Speichern.');
    exit(1);
  }

  // Sort validTasks by difficulty
  validTasks.sort((a, b) {
    final diffA = a['difficulty'] as int? ?? 1000;
    final diffB = b['difficulty'] as int? ?? 1000;
    return diffA.compareTo(diffB);
  });

  if (checkOnly) {
    print(
        '\n✅ Überprüfung erfolgreich (Dry-Run). Es wurde nichts geschrieben.');
    return;
  }

  final outputFile = File(outputPath);
  if (!outputFile.parent.existsSync()) {
    outputFile.parent.createSync(recursive: true);
  }

  final encoder = JsonEncoder.withIndent('  ');
  final jsonString = encoder.convert(validTasks);
  await outputFile.writeAsString(jsonString);

  print(
      '\n✅ Erfolgreich ${validTasks.length} Einträge nach $outputPath geschrieben.');
}

void _reportError(int index, String? id, String message, bool lenient) {
  final identifier = id != null ? 'ID "$id"' : 'Index $index';
  print('⚠️ Fehler in $identifier: $message');
}

Map<String, dynamic> _processAndValidateEntry(
    Map<String, dynamic> entry, Set<String> seenIds) {
  // 1. ID
  final id = entry['id']?.toString().trim();
  if (id == null || id.isEmpty) {
    throw Exception('Feld "id" fehlt oder ist leer.');
  }
  if (seenIds.contains(id)) {
    throw Exception('ID "$id" ist nicht eindeutig.');
  }
  seenIds.add(id);

  // 2. FEN
  final fen = entry['fen']?.toString().trim();
  if (fen == null || fen.isEmpty) {
    throw Exception('Feld "fen" fehlt oder ist leer.');
  }

  // 3. Mode
  String mode = (entry['mode']?.toString().trim()) ?? 'antiTactics';
  if (mode.isEmpty) mode = 'antiTactics';

  // 4. antiTacticsType
  final type = entry['antiTacticsType']?.toString().trim();
  if (type != 'winningTacticExists' && type != 'noWinningTactic') {
    throw Exception(
        'Ungültiger "antiTacticsType": $type. Muss "winningTacticExists" oder "noWinningTactic" sein.');
  }

  // 5. expectedMoves
  final expectedMovesRaw = entry['expectedMoves'];
  List<String> expectedMoves = [];
  if (expectedMovesRaw is List) {
    expectedMoves = expectedMovesRaw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  } else if (expectedMovesRaw is String) {
    expectedMoves = expectedMovesRaw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  if (type == 'winningTacticExists' && expectedMoves.isEmpty) {
    throw Exception(
        'Wenn "winningTacticExists", muss "expectedMoves" mindestens einen Zug enthalten.');
  }
  if (type == 'noWinningTactic' && expectedMoves.isNotEmpty) {
    throw Exception('Wenn "noWinningTactic", muss "expectedMoves" leer sein.');
  }

  // 6. difficulty
  int difficulty = 1000;
  if (entry['difficulty'] != null) {
    final parsed = int.tryParse(entry['difficulty'].toString());
    if (parsed == null) {
      throw Exception('Feld "difficulty" muss eine Zahl sein.');
    }
    if (parsed < 100 || parsed > 3000) {
      throw Exception('Feld "difficulty" muss zwischen 100 und 3000 liegen.');
    }
    difficulty = parsed;
  }

  // 7. tags
  final tagsRaw = entry['tags'];
  List<String> tags = [];
  if (tagsRaw is List) {
    tags = tagsRaw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  } else if (tagsRaw is String) {
    tags = tagsRaw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  // Deduplizieren & sortieren
  tags = tags.toSet().toList()..sort();

  // 8. phase
  final phase = entry['phase']?.toString().trim();
  if (phase != null &&
      phase.isNotEmpty &&
      phase != 'opening' &&
      phase != 'middlegame' &&
      phase != 'endgame') {
    throw Exception(
        'Ungültige "phase": $phase. Darf nur "opening", "middlegame", "endgame" oder null sein.');
  }

  // 9. Strings Normalisieren (explanation)
  final expShort = entry['explanationShort']?.toString().trim();
  final expLong = entry['explanation']?.toString().trim();

  // Output Mapping - Konsistente Reihenfolge
  return {
    'id': id,
    'fen': fen,
    'mode': mode,
    'antiTacticsType': type,
    'expectedMoves': expectedMoves,
    'difficulty': difficulty,
    if (tags.isNotEmpty) 'tags': tags,
    if (phase != null && phase.isNotEmpty) 'phase': phase,
    if (expShort != null && expShort.isNotEmpty) 'explanationShort': expShort,
    if (expLong != null && expLong.isNotEmpty) 'explanation': expLong,
  };
}
