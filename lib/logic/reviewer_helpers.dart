import 'dart:convert';
import 'dart:io';

/// Shared Export-Logik, wiederverwendbar aus CLI-Tool und Reviewer-UI.
/// Kein doppelter Code mehr zwischen review_anti_tactics_candidates.dart und main_reviewer.dart.
class ReviewExporter {
  static const String defaultExportPath = 'assets/data/anti_tactics_tasks.json';

  /// Exportiert alle 'approved' und 'pending_auto_approve' Einträge aus review_candidates.
  /// [merge] = true: fügt neue IDs in bestehende Asset-Datei ein (Duplikat-Check).
  /// Gibt eine Map mit Statistiken zurück.
  static Future<Map<String, int>> export(
    List<Map<String, dynamic>> reviewCandidates, {
    required String outputPath,
    bool merge = false,
  }) async {
    final List<Map<String, dynamic>> toExport = [];
    int rejected = 0;

    for (final entry in reviewCandidates) {
      final review = entry['review'] as Map<String, dynamic>?;
      if (review == null) {
        rejected++;
        continue;
      }

      final status = review['reviewStatus'] as String? ?? '';
      if (status != 'approved' && status != 'pending_auto_approve') {
        rejected++;
        continue;
      }

      final finalTypeRaw =
          review['finalType'] as String? ?? 'winningTacticExists';
      String antiTacticsType = finalTypeRaw;
      final tags = List<String>.from(entry['tags'] ?? []);

      // deceptiveNoTactic => noWinningTactic + Tags
      if (finalTypeRaw == 'deceptiveNoTactic') {
        antiTacticsType = 'noWinningTactic';
        if (!tags.contains('deceptive')) tags.add('deceptive');
        if (!tags.contains('fakeTactic')) tags.add('fakeTactic');
      }

      final expShort = review['finalExplanationShort']?.toString().trim() ?? '';
      final expLong = review['finalExplanation']?.toString().trim() ?? '';

      final mappedTask = <String, dynamic>{
        'id': entry['id'],
        'fen': entry['fen'],
        'mode': 'antiTactics',
        'antiTacticsType': antiTacticsType,
        'expectedMoves': entry['expectedMoves'] ?? [],
        'difficulty': entry['difficulty'] ?? 1500,
        if (entry['version'] != null) 'version': entry['version'],
        if (tags.isNotEmpty) 'tags': tags,
        if (entry['phase'] != null && entry['phase'].toString().isNotEmpty)
          'phase': entry['phase'],
        if (expShort.isNotEmpty) 'explanationShort': expShort,
        if (expLong.isNotEmpty) 'explanation': expLong,
      };

      toExport.add(mappedTask);
    }

    List<Map<String, dynamic>> finalAssets = [];
    final outputFile = File(outputPath);

    if (merge && outputFile.existsSync()) {
      try {
        final existing = jsonDecode(await outputFile.readAsString()) as List;
        finalAssets = existing.cast<Map<String, dynamic>>().toList();
      } catch (_) {}
    }

    int added = 0, updated = 0;
    for (final item in toExport) {
      final idx = finalAssets.indexWhere((e) => e['id'] == item['id']);
      if (idx >= 0) {
        finalAssets[idx] = item;
        updated++;
      } else {
        finalAssets.add(item);
        added++;
      }
    }

    finalAssets.sort((a, b) => ((a['difficulty'] as int?) ?? 1000)
        .compareTo((b['difficulty'] as int?) ?? 1000));

    if (!outputFile.parent.existsSync()) {
      outputFile.parent.createSync(recursive: true);
    }
    await outputFile
        .writeAsString(JsonEncoder.withIndent('  ').convert(finalAssets));

    return {
      'exported': toExport.length,
      'added': added,
      'updated': updated,
      'skipped': rejected
    };
  }
}

/// Review-Metriken, live aus dem Kandidaten-Datensatz berechnet.
class ReviewMetrics {
  final int total;
  final int pending;
  final int approved;
  final int autoApprove;
  final int rejected;
  final int needsEdit;
  final int deceptive;
  final int winning;
  final int noWinning;

  const ReviewMetrics({
    required this.total,
    required this.pending,
    required this.approved,
    required this.autoApprove,
    required this.rejected,
    required this.needsEdit,
    required this.deceptive,
    required this.winning,
    required this.noWinning,
  });

  int get reviewed => approved + autoApprove + rejected;
  double get progressPercent => total == 0 ? 0 : (reviewed / total * 100);

  factory ReviewMetrics.from(List<Map<String, dynamic>> candidates) {
    int pending = 0, approved = 0, auto = 0, rejected = 0, needsEdit = 0;
    int deceptive = 0, winning = 0, noWinning = 0;

    for (final c in candidates) {
      final r = c['review'] as Map<String, dynamic>? ?? {};
      final status = r['reviewStatus'] as String? ?? 'pending_review';
      final type = r['finalType'] as String? ?? '';

      switch (status) {
        case 'pending_review':
          pending++;
          break;
        case 'pending_auto_approve':
          auto++;
          break;
        case 'approved':
          approved++;
          break;
        case 'rejected':
          rejected++;
          break;
        case 'needsEdit':
          needsEdit++;
          break;
        default:
          pending++;
      }

      if (type == 'deceptiveNoTactic')
        deceptive++;
      else if (type == 'winningTacticExists')
        winning++;
      else if (type == 'noWinningTactic') noWinning++;
    }

    return ReviewMetrics(
      total: candidates.length,
      pending: pending,
      approved: approved,
      autoApprove: auto,
      rejected: rejected,
      needsEdit: needsEdit,
      deceptive: deceptive,
      winning: winning,
      noWinning: noWinning,
    );
  }
}
