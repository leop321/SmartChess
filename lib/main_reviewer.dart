import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'logic/reviewer_helpers.dart';
import 'model/app_themes.dart';
import 'views/components/tactics_view/tactics_board_widget.dart';

/// Lokaler Dataset-Kurations-Editor.
///
/// Start-Kommando:
///   flutter run -t lib/main_reviewer.dart -d windows
///
/// Shortcuts:
///   A = Approve     R = Reject      P = Pending
///   1 = Winning     2 = Deceptive   3 = No Win
///   N = Next Pending
///   ↑/↓ = Navigate  Ctrl+S = Save   Ctrl+E = Export
void main() {
  runApp(const ReviewerApp());
}

class ReviewerApp extends StatelessWidget {
  const ReviewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anti-Tactics Dataset Reviewer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF141414),
        cardColor: const Color(0xFF232323),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF5B8CF8),
          secondary: Color(0xFF4CAF50),
        ),
      ),
      home: const DatasetReviewView(),
    );
  }
}

// ─── Filter-Enum ───────────────────────────────────────────────────────────
enum StatusFilter { all, pending, autoApprove, approved, rejected, needsEdit }

// ─── Stateful main view ────────────────────────────────────────────────────
class DatasetReviewView extends StatefulWidget {
  const DatasetReviewView({super.key});
  @override
  State<DatasetReviewView> createState() => _DatasetReviewViewState();
}

class _DatasetReviewViewState extends State<DatasetReviewView> {
  // ── Data ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _allCandidates = [];
  List<int> _filteredIndices = []; // indices into _allCandidates
  int _filteredPos = 0; // current position in _filteredIndices

  bool _isLoading = true;
  bool _hasUnsavedChanges = false;
  bool _mergeOnExport = false;
  String _exportPath = ReviewExporter.defaultExportPath;

  // ── Filter & Search ───────────────────────────────────────────────────────
  StatusFilter _statusFilter = StatusFilter.all;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // ── Editor fields ─────────────────────────────────────────────────────────
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _expShortCtrl = TextEditingController();
  final TextEditingController _expCtrl = TextEditingController();
  String _currentStatus = 'pending_review';
  String _currentFinalType = 'winningTacticExists';

  String _filePath = 'tool/review_candidates.json';

  // ── Getters ───────────────────────────────────────────────────────────────
  int get _globalIndex =>
      _filteredIndices.isEmpty ? 0 : _filteredIndices[_filteredPos];

  Map<String, dynamic>? get _currentCandidate =>
      _allCandidates.isEmpty ? null : _allCandidates[_globalIndex];

  ReviewMetrics get _metrics => ReviewMetrics.from(_allCandidates);

  // ─── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _expShortCtrl.dispose();
    _expCtrl.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ─── Data IO ──────────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    try {
      final file = File(_filePath);
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString()) as List;
        setState(() {
          _allCandidates = raw.cast<Map<String, dynamic>>().toList();
          _isLoading = false;
        });
        _rebuildFilter();
        if (_filteredIndices.isNotEmpty) _populateFields();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveData() async {
    _commitEditorToModel();
    try {
      await File(_filePath)
          .writeAsString(JsonEncoder.withIndent('  ').convert(_allCandidates));
      setState(() => _hasUnsavedChanges = false);
      _snack('✅ Gespeichert!', Colors.green);
    } catch (e) {
      _snack('❌ Speichern fehlgeschlagen: $e', Colors.red);
    }
  }

  Future<void> _exportApproved() async {
    _commitEditorToModel();
    try {
      final stats = await ReviewExporter.export(
        _allCandidates,
        outputPath: _exportPath,
        merge: _mergeOnExport,
      );
      _snack(
          '✅ Export: +${stats['added']} neu, ${stats['updated']} updated → $_exportPath',
          Colors.green);
    } catch (e) {
      _snack('❌ Export fehlgeschlagen: $e', Colors.red);
    }
  }

  // ─── Filter & Navigation ──────────────────────────────────────────────────
  void _rebuildFilter() {
    final currentGlobal = _filteredIndices.isEmpty ? -1 : _globalIndex;

    final newIndices = <int>[];
    for (int i = 0; i < _allCandidates.length; i++) {
      final c = _allCandidates[i];
      final review = c['review'] as Map<String, dynamic>? ?? {};
      final status = review['reviewStatus'] as String? ?? 'pending_review';

      // Status filter
      bool statusOk = switch (_statusFilter) {
        StatusFilter.all => true,
        StatusFilter.pending => status == 'pending_review',
        StatusFilter.autoApprove => status == 'pending_auto_approve',
        StatusFilter.approved => status == 'approved',
        StatusFilter.rejected => status == 'rejected',
        StatusFilter.needsEdit => status == 'needsEdit',
      };
      if (!statusOk) continue;

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final id = c['id']?.toString().toLowerCase() ?? '';
        final tags = (c['tags'] as List?)
                ?.map((t) => t.toString().toLowerCase())
                .join(' ') ??
            '';
        if (!id.contains(_searchQuery) && !tags.contains(_searchQuery))
          continue;
      }

      newIndices.add(i);
    }

    setState(() {
      _filteredIndices = newIndices;
      // Try to stay on same global entry
      final newPos = newIndices.indexOf(currentGlobal);
      _filteredPos = newPos >= 0 ? newPos : 0;
    });
  }

  void _goTo(int filteredPos) {
    if (_filteredIndices.isEmpty) return;
    _commitEditorToModel();
    setState(() {
      _filteredPos = filteredPos.clamp(0, _filteredIndices.length - 1);
    });
    _populateFields();
  }

  void _goNext() {
    if (_filteredPos < _filteredIndices.length - 1) _goTo(_filteredPos + 1);
  }

  void _goPrev() {
    if (_filteredPos > 0) _goTo(_filteredPos - 1);
  }

  void _goNextPending() {
    // Find next pending from current position in ALL candidates
    final start = _filteredIndices.isEmpty ? 0 : (_globalIndex + 1);
    for (int i = start; i < _allCandidates.length; i++) {
      final status = (_allCandidates[i]['review']
              as Map<String, dynamic>?)?['reviewStatus'] as String? ??
          '';
      if (status == 'pending_review' || status == 'pending_auto_approve') {
        // Switch filter to all so we can see it
        setState(() => _statusFilter = StatusFilter.all);
        _rebuildFilter();
        final pos = _filteredIndices.indexOf(i);
        if (pos >= 0) _goTo(pos);
        return;
      }
    }
    _snack('Keine weiteren pending Einträge.', Colors.amber);
  }

  // ─── Editor sync ──────────────────────────────────────────────────────────
  void _populateFields() {
    final c = _currentCandidate;
    if (c == null) return;
    final r = c['review'] as Map<String, dynamic>? ?? {};
    setState(() {
      _currentStatus = r['reviewStatus'] as String? ?? 'pending_review';
      _currentFinalType = r['finalType'] as String? ?? 'winningTacticExists';
    });
    _notesCtrl.text = r['reviewNotes'] as String? ?? '';
    _expShortCtrl.text = r['finalExplanationShort'] as String? ?? '';
    _expCtrl.text = r['finalExplanation'] as String? ?? '';
  }

  void _commitEditorToModel() {
    final c = _currentCandidate;
    if (c == null) return;
    final r = c['review'] as Map<String, dynamic>? ?? {};
    r['reviewStatus'] = _currentStatus;
    r['finalType'] = _currentFinalType;
    r['reviewNotes'] = _notesCtrl.text;
    r['finalExplanationShort'] = _expShortCtrl.text;
    r['finalExplanation'] = _expCtrl.text;
    r['reviewedAt'] = DateTime.now().toIso8601String();
    _hasUnsavedChanges = true;
  }

  void _setStatus(String s) {
    setState(() => _currentStatus = s);
    _hasUnsavedChanges = true;
  }

  void _setFinalType(String t) {
    setState(() => _currentFinalType = t);
    _hasUnsavedChanges = true;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color.withValues(alpha: 0.85),
      duration: const Duration(seconds: 2),
    ));
  }

  Color _statusColor(String s) => switch (s) {
        'approved' => Colors.green,
        'rejected' => Colors.red,
        'pending_auto_approve' => Colors.blue,
        'needsEdit' => Colors.orange,
        _ => Colors.amber,
      };

  Color _typeColor(String t) => switch (t) {
        'winningTacticExists' => const Color(0xFF5B8CF8),
        'deceptiveNoTactic' => Colors.deepOrange,
        'noWinningTactic' => Colors.teal,
        _ => Colors.grey,
      };

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_allCandidates.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_open, size: 64, color: Colors.white30),
              const SizedBox(height: 16),
              const Text('Keine review_candidates.json gefunden.',
                  style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              Text('Pfad: $_filePath',
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 16),
              Text(
                  'Führe zuerst aus:\ndart run tool/review_anti_tactics_candidates.dart --action=prepare',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: _buildShortcuts(),
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: _buildAppBar(),
          body: Column(
            children: [
              _buildMetricsBar(),
              _buildToolbar(),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildListPane(),
                    const VerticalDivider(width: 1),
                    _buildBoardPane(),
                    const VerticalDivider(width: 1),
                    _buildEditorPane(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> _buildShortcuts() => {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _saveData,
        const SingleActivator(LogicalKeyboardKey.keyE, control: true):
            _exportApproved,
        const SingleActivator(LogicalKeyboardKey.keyA): () =>
            _setStatus('approved'),
        const SingleActivator(LogicalKeyboardKey.keyR): () =>
            _setStatus('rejected'),
        const SingleActivator(LogicalKeyboardKey.keyP): () =>
            _setStatus('pending_review'),
        const SingleActivator(LogicalKeyboardKey.digit1): () =>
            _setFinalType('winningTacticExists'),
        const SingleActivator(LogicalKeyboardKey.digit2): () =>
            _setFinalType('deceptiveNoTactic'),
        const SingleActivator(LogicalKeyboardKey.digit3): () =>
            _setFinalType('noWinningTactic'),
        const SingleActivator(LogicalKeyboardKey.keyN): _goNextPending,
        const SingleActivator(LogicalKeyboardKey.arrowDown): _goNext,
        const SingleActivator(LogicalKeyboardKey.arrowUp): _goPrev,
      };

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Row(
        children: [
          const Text('Anti-Tactics Reviewer'),
          const SizedBox(width: 16),
          DropdownButton<String>(
            value: _filePath,
            dropdownColor: const Color(0xFF232323),
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(
                value: 'tool/review_candidates.json',
                child: Text('V1 (Deceptive)'),
              ),
              DropdownMenuItem(
                value: 'tool/review_candidates_v2.json',
                child: Text('V2 (Best Move)'),
              ),
            ],
            onChanged: (val) {
              if (val != null && val != _filePath) {
                if (_hasUnsavedChanges) _saveData();
                setState(() {
                  _filePath = val;
                  _isLoading = true;
                  _allCandidates = [];
                  _filteredIndices = [];
                });
                _loadData();
              }
            },
          ),
          const SizedBox(width: 12),
          if (_hasUnsavedChanges)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
              ),
              child: const Text('Unsaved',
                  style: TextStyle(fontSize: 11, color: Colors.orange)),
            ),
          const Spacer(),
          Text(
            '${_filteredPos + 1} / ${_filteredIndices.length}'
            ' (total: ${_allCandidates.length})',
            style: const TextStyle(fontSize: 13, color: Colors.white54),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.save),
          tooltip: 'Speichern (Ctrl+S)',
          onPressed: _saveData,
        ),
        IconButton(
          icon: const Icon(Icons.upload),
          tooltip: 'Export Approved (Ctrl+E)',
          onPressed: _exportApproved,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildMetricsBar() {
    final m = _metrics;
    return Container(
      height: 40,
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _metricChip('Total', m.total, Colors.white54),
          _metricChip('Pending', m.pending, Colors.amber),
          _metricChip('Auto', m.autoApprove, Colors.blue),
          _metricChip('Approved', m.approved, Colors.green),
          _metricChip('Rejected', m.rejected, Colors.red),
          const SizedBox(width: 16),
          _metricChip('Winning', m.winning, const Color(0xFF5B8CF8)),
          _metricChip('Deceptive', m.deceptive, Colors.deepOrange),
          _metricChip('No Win', m.noWinning, Colors.teal),
          const Spacer(),
          Text(
            '${m.progressPercent.toStringAsFixed(0)}% reviewed',
            style: const TextStyle(fontSize: 12, color: Colors.white38),
          ),
          const SizedBox(width: 12),
          // Export merge toggle
          Row(
            children: [
              const Text('Merge',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
              Switch(
                value: _mergeOnExport,
                onChanged: (v) => setState(() => _mergeOnExport = v),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricChip(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text('$label: $count', style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 48,
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Status filter chips
          ...[
            ('All', StatusFilter.all, Colors.white54),
            ('Pending', StatusFilter.pending, Colors.amber),
            ('Auto', StatusFilter.autoApprove, Colors.blue),
            ('Approved', StatusFilter.approved, Colors.green),
            ('Rejected', StatusFilter.rejected, Colors.red),
          ].map((e) {
            final isSelected = _statusFilter == e.$2;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(e.$1, style: TextStyle(fontSize: 12, color: e.$3)),
                selected: isSelected,
                onSelected: (_) {
                  setState(() => _statusFilter = e.$2);
                  _rebuildFilter();
                },
                selectedColor: e.$3.withValues(alpha: 0.2),
                checkmarkColor: e.$3,
                side: BorderSide(color: isSelected ? e.$3 : Colors.white12),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            );
          }),
          const SizedBox(width: 8),
          // Search
          SizedBox(
            width: 200,
            height: 34,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'id / tag suchen...',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 16),
              ),
              onChanged: (v) {
                _searchQuery = v.toLowerCase();
                _rebuildFilter();
              },
            ),
          ),
          const SizedBox(width: 8),
          // Nav buttons
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 18),
            tooltip: 'Vorheriger (↑)',
            onPressed: _goPrev,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 18),
            tooltip: 'Nächster (↓)',
            onPressed: _goNext,
          ),
          IconButton(
            icon: const Icon(Icons.skip_next, size: 18),
            tooltip: 'Nächster Pending (N)',
            onPressed: _goNextPending,
          ),
          const Spacer(),
          Text(_filePath,
              style: const TextStyle(fontSize: 11, color: Colors.white24)),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildListPane() {
    return SizedBox(
      width: 240,
      child: ListView.builder(
        itemCount: _filteredIndices.length,
        itemBuilder: (context, pos) {
          final globalIdx = _filteredIndices[pos];
          final c = _allCandidates[globalIdx];
          final r = c['review'] as Map<String, dynamic>? ?? {};
          final status = r['reviewStatus'] as String? ?? '';
          final type = r['finalType'] as String? ?? '';
          final isSelected = pos == _filteredPos;

          return ListTile(
            dense: true,
            selected: isSelected,
            selectedTileColor: const Color(0xFF2A3A5A),
            leading: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _statusColor(status),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 10,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _typeColor(type),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
            title: Text(
              c['id']?.toString() ?? '-',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              'Δ${(c['analysis'] as Map?)?['scoreGap'] ?? '?'} | Diff ${c['difficulty'] ?? '?'}',
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
            onTap: () => _goTo(pos),
          );
        },
      ),
    );
  }

  Widget _buildBoardPane() {
    final c = _currentCandidate;
    if (c == null)
      return const Expanded(flex: 3, child: Center(child: Text('–')));

    final fen = c['fen'] as String? ?? '';
    final analysis = c['analysis'] as Map<String, dynamic>? ?? {};
    final deceptiveMove = analysis['deceptiveCandidateMove'] as String?;
    final engineBest = analysis['engineBestMove'] as String?;

    return Expanded(
      flex: 3,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: TacticsBoardWidget(
                  theme: themeList.first,
                  pieceTheme: 'Classic',
                  fen: fen,
                  lastMovePair: engineBest,
                  onTileTap: (_) {},
                ),
              ),
            ),
          ),
          // Quick-action row under board
          Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                if (deceptiveMove != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          Border.all(color: Colors.red.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '🚨 Deceptive: $deceptiveMove verliert deutlich!',
                      style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Row(
                  children: [
                    _quickBtn('A Approve', Colors.green, () {
                      _setStatus('approved');
                      _goNext();
                    }),
                    const SizedBox(width: 6),
                    _quickBtn('R Reject', Colors.red, () {
                      _setStatus('rejected');
                      _goNext();
                    }),
                    const SizedBox(width: 6),
                    _quickBtn('P Pending', Colors.amber,
                        () => _setStatus('pending_review')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickBtn(String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.3)),
          padding: const EdgeInsets.symmetric(vertical: 6),
          minimumSize: const Size(0, 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildEditorPane() {
    final c = _currentCandidate;
    if (c == null) return const Expanded(flex: 3, child: SizedBox());

    final analysis = c['analysis'] as Map<String, dynamic>? ?? {};
    final candidateAnalyses = (analysis['candidateAnalyses'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final tags = (c['tags'] as List?)?.map((t) => t.toString()).toList() ?? [];

    return Expanded(
      flex: 3,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ── Puzzle Info Card ─────────────────────────────────────────────
          _sectionCard('Puzzle Info', [
            _infoRow('ID', c['id']?.toString() ?? '-'),
            _infoRow('Difficulty', c['difficulty']?.toString() ?? '-'),
            _infoRow('Phase', c['phase']?.toString() ?? '-'),
            _infoRow('Expected',
                (c['expectedMoves'] as List?)?.join(', ') ?? '(none)'),
            Wrap(
              spacing: 4,
              children: tags
                  .map((t) => Chip(
                        label: Text(t, style: const TextStyle(fontSize: 10)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ]),
          const SizedBox(height: 10),

          // ── Engine Analysis Card ─────────────────────────────────────────
          _sectionCard('Engine Analyse', [
            _infoRow(
                'Best Move', analysis['engineBestMove']?.toString() ?? '-'),
            _infoRow('Score Gap', '${analysis['scoreGap'] ?? '-'} cp'),
            _infoRow('Suggested', analysis['suggestedType']?.toString() ?? '-'),
            _infoRow('Reason', analysis['reviewReason']?.toString() ?? '-'),
          ]),
          const SizedBox(height: 10),

          // ── Candidate Analyses ───────────────────────────────────────────
          if (candidateAnalyses.isNotEmpty) ...[
            _sectionCard('Kandidaten-Analyse', [
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(2),
                  3: FlexColumnWidth(2),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05)),
                    children: ['Move', 'Cat', 'Delta', 'Score']
                        .map((h) => Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 3),
                              child: Text(h,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white54)),
                            ))
                        .toList(),
                  ),
                  ...candidateAnalyses.map((ca) {
                    final delta = (ca['deltaFromBest'] as int?) ?? 0;
                    final isDeceptive = delta >= 150 &&
                        (ca['category'] == 'check' ||
                            ca['category'] == 'capture');
                    final score = ca['scoreMate'] != null
                        ? 'M${ca['scoreMate']}'
                        : '${ca['scoreCp'] ?? '?'}';
                    return TableRow(
                      decoration: BoxDecoration(
                        color: isDeceptive
                            ? Colors.red.withValues(alpha: 0.1)
                            : null,
                      ),
                      children: [
                        _tableCell(ca['move']?.toString() ?? '-',
                            color: isDeceptive ? Colors.redAccent : null),
                        _tableCell(ca['category']?.toString() ?? '-'),
                        _tableCell(isDeceptive ? '⚠ $delta' : '$delta',
                            color: delta > 300
                                ? Colors.red
                                : (delta > 100 ? Colors.orange : Colors.green)),
                        _tableCell(score),
                      ],
                    );
                  }),
                ],
              ),
            ]),
            const SizedBox(height: 10),
          ],

          // ── Review Status ─────────────────────────────────────────────────
          const Text('Status  (A/R/P)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'pending_review',
                  label: Text('Pending', style: TextStyle(fontSize: 11))),
              ButtonSegment(
                  value: 'pending_auto_approve',
                  label: Text('Auto', style: TextStyle(fontSize: 11))),
              ButtonSegment(
                  value: 'approved',
                  label: Text('Approved', style: TextStyle(fontSize: 11))),
              ButtonSegment(
                  value: 'rejected',
                  label: Text('Rejected', style: TextStyle(fontSize: 11))),
            ],
            selected: {_currentStatus},
            onSelectionChanged: (s) => _setStatus(s.first),
          ),
          const SizedBox(height: 12),

          // ── Final Type ────────────────────────────────────────────────────
          const Text('Final Type  (1 / 2 / 3)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'winningTacticExists',
                  label: Text('Winning', style: TextStyle(fontSize: 11))),
              ButtonSegment(
                  value: 'deceptiveNoTactic',
                  label: Text('Deceptive', style: TextStyle(fontSize: 11))),
              ButtonSegment(
                  value: 'noWinningTactic',
                  label: Text('No Win', style: TextStyle(fontSize: 11))),
            ],
            selected: {_currentFinalType},
            onSelectionChanged: (s) => _setFinalType(s.first),
          ),
          const SizedBox(height: 12),

          // ── Text fields ───────────────────────────────────────────────────
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
              labelText: 'Review Notes (intern)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLines: 2,
            onChanged: (_) => _hasUnsavedChanges = true,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _expShortCtrl,
            decoration: const InputDecoration(
              labelText: 'Explanation Short (UI)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _hasUnsavedChanges = true,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _expCtrl,
            decoration: const InputDecoration(
              labelText: 'Explanation Long',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLines: 3,
            onChanged: (_) => _hasUnsavedChanges = true,
          ),
          const SizedBox(height: 16),

          // Export Pfad
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: _exportPath),
                  decoration: const InputDecoration(
                    labelText: 'Export-Pfad',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (v) => _exportPath = v,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _exportApproved,
                icon: const Icon(Icons.upload, size: 16),
                label: const Text('Export'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E4A2E),
                  foregroundColor: Colors.green,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, List<Widget> children) {
    return Card(
      color: const Color(0xFF232323),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.white70)),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.white38)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _tableCell(String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              color: color ?? Colors.white70,
              fontWeight: color != null ? FontWeight.bold : FontWeight.normal)),
    );
  }
}
