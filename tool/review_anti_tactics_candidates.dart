import 'dart:convert';
import 'dart:io';

/// Lokales Offline-Tool zum Reviewen und Exportieren von Anti-Tactics Kandidaten.
///
/// Modus 1 (Prepare): Wandelt einen Engine-Analyse-Report in eine reviewbare Datei um.
/// Modus 2 (Export): Nimmt die reviewbare Datei, filtert nach 'approved' und exportiert sie
///                   in das finale App-Schema (optional mit Merge in bestehende Assets).
///
/// Aufruf:
/// dart run tool/review_anti_tactics_candidates.dart --action=prepare [options]
/// dart run tool/review_anti_tactics_candidates.dart --action=export [options]
///
/// Optionen (Prepare):
///   --input=<pfad>        (Standard: tool/analysis_report.json)
///   --output=<pfad>       (Standard: tool/review_candidates.json)
///
/// Optionen (Export):
///   --input=<pfad>        (Standard: tool/review_candidates.json)
///   --output=<pfad>       (Standard: assets/data/anti_tactics_tasks.json)
///   --merge-into-existing (Fügt neue Einträge in bestehende Assets ein)

void main(List<String> arguments) async {
  String action = 'prepare';
  String inputPath = '';
  String outputPath = '';
  bool mergeIntoExisting = false;

  for (final arg in arguments) {
    if (arg.startsWith('--action='))
      action = arg.substring('--action='.length);
    else if (arg.startsWith('--input='))
      inputPath = arg.substring('--input='.length);
    else if (arg.startsWith('--output='))
      outputPath = arg.substring('--output='.length);
    else if (arg == '--merge-into-existing') mergeIntoExisting = true;
  }

  if (action == 'prepare') {
    if (inputPath.isEmpty) inputPath = 'tool/analysis_report.json';
    if (outputPath.isEmpty) outputPath = 'tool/review_candidates.json';
    await _prepareReview(inputPath, outputPath);
  } else if (action == 'export') {
    if (inputPath.isEmpty) inputPath = 'tool/review_candidates.json';
    if (outputPath.isEmpty) outputPath = 'assets/data/anti_tactics_tasks.json';
    await _exportApproved(inputPath, outputPath, mergeIntoExisting);
  } else {
    print('❌ Unbekannte Aktion: $action. Erlaubt sind "prepare" und "export".');
    exit(1);
  }
}

/// --- MODUS 1: PREPARE ---
/// Nimmt den reinen Engine-Report und bereitet ein Review-Dokument vor,
/// in dem der Mensch nur noch "status" und "finalExplanation" pflegen muss.
Future<void> _prepareReview(String inputPath, String outputPath) async {
  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    print('❌ Eingabedatei existiert nicht: $inputPath');
    exit(1);
  }

  print('Lese Analyse-Report aus $inputPath...');
  final List<dynamic> rawData = jsonDecode(await inputFile.readAsString());
  final List<Map<String, dynamic>> reviewData = [];
  int autoApproved = 0;
  int pending = 0;

  for (final entry in rawData.cast<Map<String, dynamic>>()) {
    final analysis = entry['analysis'] as Map<String, dynamic>?;
    if (analysis == null) continue;

    final suggestedType = analysis['suggestedType'] as String?;
    final engineMatchesExpected =
        analysis['expectedMatchesEngine'] as bool? ?? false;
    // Default Review-Status Heuristik
    String status = 'pending';
    String finalType =
        suggestedType ?? entry['antiTacticsType'] ?? 'winningTacticExists';
    String finalExplanationShort = entry['explanationShort'] ?? '';

    // Automatische Freigabe-Empfehlung für SEHR eindeutige Fälle
    if (suggestedType == 'winningTacticExists' && engineMatchesExpected) {
      status =
          'pending_auto_approve'; // Der Mensch muss es trotzdem absegnen, aber es ist klar
      finalExplanationShort = 'Gewinnbringende Taktik';
    } else if (suggestedType == 'deceptiveNoTactic') {
      status = 'pending_review';
      finalExplanationShort = 'Achtung Falle: Falscher Zug verliert';
    }

    final reviewSection = {
      'reviewStatus': status,
      'reviewedBy': '',
      'reviewedAt': '',
      'reviewNotes': analysis['reviewReason'] ?? '',
      'finalType': finalType,
      'finalExplanationShort': finalExplanationShort,
      'finalExplanation': entry['explanation'] ?? '',
    };

    final reviewEntry = {
      '_summary':
          '${entry['id']} - Engine: $suggestedType - Gap: ${analysis['scoreGap']}',
      'id': entry['id'],
      'fen': entry['fen'],
      'expectedMoves': entry['expectedMoves'],
      'difficulty': entry['difficulty'],
      'tags': entry['tags'] ?? [],
      'phase': entry['phase'] ?? '',
      'review': reviewSection,
      'analysis':
          analysis, // Wir behalten die Engine-Details zum Nachschlagen bei
    };

    reviewData.add(reviewEntry);
    if (status.contains('auto_approve'))
      autoApproved++;
    else
      pending++;
  }

  final outputFile = File(outputPath);
  if (!outputFile.parent.existsSync())
    outputFile.parent.createSync(recursive: true);
  await outputFile
      .writeAsString(JsonEncoder.withIndent('  ').convert(reviewData));

  print('✅ Review-File erstellt unter $outputPath');
  print('   -> $autoApproved Einträge sind klare Auto-Approve-Kandidaten.');
  print('   -> $pending Einträge brauchen menschliche Entscheidungen.');
}

/// --- MODUS 2: EXPORT ---
/// Liest das (vermutlich von einem Menschen editierte) Review-JSON,
/// filtert nach "approved" und transformiert in das finale App-Schema.
Future<void> _exportApproved(
    String inputPath, String outputPath, bool merge) async {
  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    print('❌ Review-Datei existiert nicht: $inputPath');
    exit(1);
  }

  print('Lese Review-Datei aus $inputPath...');
  final List<dynamic> reviewRaw = jsonDecode(await inputFile.readAsString());
  final List<Map<String, dynamic>> toExport = [];
  int rejectedOrPending = 0;

  for (final entry in reviewRaw.cast<Map<String, dynamic>>()) {
    final review = entry['review'] as Map<String, dynamic>?;
    if (review == null) continue;

    final status = review['reviewStatus'] as String;

    // Wir exportieren auch pending_auto_approve zum Testen, im produktiven Workflow
    // sollte der Mensch diese aber erst auf "approved" setzen.
    if (status != 'approved' && status != 'pending_auto_approve') {
      rejectedOrPending++;
      continue;
    }

    final finalTypeRaw = review['finalType'] as String;
    String antiTacticsType = finalTypeRaw;
    final tags = List<String>.from(entry['tags'] ?? []);

    // **ENTSCHEIDUNG: Wie mappen wir deceptiveNoTactic in die App?**
    // Die App kennt im Controller nur "winningTacticExists" oder "noWinningTactic" (harte Bool-Logik!).
    // "Deceptive" ist kein eigener Logik-Pfad, sondern eine inhaltliche UX/Didaktik-Eigenschaft.
    // Daher: Wenn der Reviewer "deceptiveNoTactic" wählt, markieren wir die Aufgabe
    // für die App-Logik als "noWinningTactic" und fügen die Tags "deceptive" und "fakeTactic" hinzu.
    if (finalTypeRaw == 'deceptiveNoTactic') {
      antiTacticsType = 'noWinningTactic';
      if (!tags.contains('deceptive')) tags.add('deceptive');
      if (!tags.contains('fakeTactic')) tags.add('fakeTactic');
    }

    final mappedTask = {
      'id': entry['id'],
      'fen': entry['fen'],
      'mode': 'antiTactics', // Final mode
      'antiTacticsType': antiTacticsType,
      'expectedMoves': entry['expectedMoves'] ?? [],
      'difficulty': entry['difficulty'] ?? 1500,
      if (tags.isNotEmpty) 'tags': tags,
      if (entry['phase'] != null && entry['phase'].toString().isNotEmpty)
        'phase': entry['phase'],
      if (review['finalExplanationShort'] != null &&
          review['finalExplanationShort'].toString().isNotEmpty)
        'explanationShort': review['finalExplanationShort'],
      if (review['finalExplanation'] != null &&
          review['finalExplanation'].toString().isNotEmpty)
        'explanation': review['finalExplanation'],
    };

    toExport.add(mappedTask);
  }

  // --- Merge in Existing Assets ---
  List<Map<String, dynamic>> finalAssets = [];
  final outputFile = File(outputPath);

  if (merge && outputFile.existsSync()) {
    try {
      final List<dynamic> existingData =
          jsonDecode(await outputFile.readAsString());
      finalAssets = existingData.cast<Map<String, dynamic>>().toList();
    } catch (e) {
      print(
          '⚠️ Warnung: Bestehende Datei konnte nicht gelesen werden, starte frisch.');
    }
  }

  int added = 0;
  int updated = 0;

  for (final exportedItem in toExport) {
    final existingIndex =
        finalAssets.indexWhere((e) => e['id'] == exportedItem['id']);
    if (existingIndex >= 0) {
      finalAssets[existingIndex] = exportedItem;
      updated++;
    } else {
      finalAssets.add(exportedItem);
      added++;
    }
  }

  // Stable Sort nach Difficulty
  finalAssets.sort((a, b) {
    final diffA = a['difficulty'] as int? ?? 1000;
    final diffB = b['difficulty'] as int? ?? 1000;
    return diffA.compareTo(diffB);
  });

  if (!outputFile.parent.existsSync())
    outputFile.parent.createSync(recursive: true);
  await outputFile
      .writeAsString(JsonEncoder.withIndent('  ').convert(finalAssets));

  print('✅ Export abgeschlossen. Zieldatei: $outputPath');
  print(
      '   -> Exportiert: ${toExport.length} Einträge (Ignoriert/Pending: $rejectedOrPending)');
  if (merge) {
    print('   -> Neu hinzugefügt: $added | Aktualisiert: $updated');
    print('   -> Gesamte Asset-Puzzles nun: ${finalAssets.length}');
  }
}
