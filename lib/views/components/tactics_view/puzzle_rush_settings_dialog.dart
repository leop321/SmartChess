import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../logic/puzzle_rush_storage.dart';
import '../../../model/puzzle_rush_config.dart';
import '../shared/glass_panel.dart';

class PuzzleRushSettingsDialog extends StatefulWidget {
  final PuzzleRushConfig initialConfig;
  final Function(PuzzleRushConfig) onStart;

  const PuzzleRushSettingsDialog({
    Key? key,
    required this.initialConfig,
    required this.onStart,
  }) : super(key: key);

  @override
  State<PuzzleRushSettingsDialog> createState() =>
      _PuzzleRushSettingsDialogState();
}

class _PuzzleRushSettingsDialogState extends State<PuzzleRushSettingsDialog> {
  late int? _durationSeconds;
  late int _lives;
  late bool _includeAntiTactics;
  late int _difficultyRampStep;

  int _highScore = 0;
  int _bestStreak = 0;
  List<PuzzleRushRunRecord> _history = [];

  @override
  void initState() {
    super.initState();
    _durationSeconds = widget.initialConfig.durationSeconds;
    _lives = widget.initialConfig.lives;
    _includeAntiTactics = widget.initialConfig.includeAntiTactics;
    _difficultyRampStep = widget.initialConfig.difficultyRampStep;
    _loadStats();
  }

  Future<void> _loadStats() async {
    final hs = await PuzzleRushStorage.loadHighScore();
    final bs = await PuzzleRushStorage.loadBestStreak();
    final hist = await PuzzleRushStorage.loadRunHistory();
    if (mounted) {
      setState(() {
        _highScore = hs;
        _bestStreak = bs;
        _history = hist;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: GlassPanel(
        borderRadius: 24,
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB74D).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: Color(0xFFFFB74D),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Puzzle Rush',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Konfiguriere deinen Challenge-Run',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Highscore Banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFFFB74D).withValues(alpha: 0.25),
                      const Color(0xFFEF7090).withValues(alpha: 0.25),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFFFB74D).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text(
                          'REKORD',
                          style: TextStyle(
                            color: Color(0xFFFFB74D),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_highScore',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    Container(height: 32, width: 1, color: Colors.white24),
                    Column(
                      children: [
                        const Text(
                          'BESTE STREAK',
                          style: TextStyle(
                            color: Color(0xFFEF7090),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_bestStreak',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Zeit-Modus
              const Text(
                'Zeitlimit',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildOptionPill(
                    label: '3 Min',
                    selected: _durationSeconds == 180,
                    onTap: () => setState(() => _durationSeconds = 180),
                  ),
                  const SizedBox(width: 8),
                  _buildOptionPill(
                    label: '5 Min',
                    selected: _durationSeconds == 300,
                    onTap: () => setState(() => _durationSeconds = 300),
                  ),
                  const SizedBox(width: 8),
                  _buildOptionPill(
                    label: 'Überleben',
                    selected: _durationSeconds == null,
                    onTap: () => setState(() => _durationSeconds = null),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Leben
              const Text(
                'Anzahl Leben',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildOptionPill(
                    label: '3 Leben',
                    selected: _lives == 3,
                    onTap: () => setState(() => _lives = 3),
                  ),
                  const SizedBox(width: 8),
                  _buildOptionPill(
                    label: '5 Leben',
                    selected: _lives == 5,
                    onTap: () => setState(() => _lives = 5),
                  ),
                  const SizedBox(width: 8),
                  _buildOptionPill(
                    label: '1 Leben',
                    selected: _lives == 1,
                    onTap: () => setState(() => _lives = 1),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Difficulty Ramp
              const Text(
                'Schwierigkeits-Steigung',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildOptionPill(
                    label: 'Langsam (+15)',
                    selected: _difficultyRampStep == 15,
                    onTap: () => setState(() => _difficultyRampStep = 15),
                  ),
                  const SizedBox(width: 8),
                  _buildOptionPill(
                    label: 'Mittel (+30)',
                    selected: _difficultyRampStep == 30,
                    onTap: () => setState(() => _difficultyRampStep = 30),
                  ),
                  const SizedBox(width: 8),
                  _buildOptionPill(
                    label: 'Schnell (+50)',
                    selected: _difficultyRampStep == 50,
                    onTap: () => setState(() => _difficultyRampStep = 50),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Anti-Tactics Switch Toggle
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.shield_moon_rounded,
                            color: Color(0xFFEF7090), size: 20),
                        SizedBox(width: 10),
                        Text(
                          'Inklusive Anti-Taktiken',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    CupertinoSwitch(
                      activeTrackColor: const Color(0xFFFFB74D),
                      value: _includeAntiTactics,
                      onChanged: (val) =>
                          setState(() => _includeAntiTactics = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Historie der letzten Runs
              if (_history.isNotEmpty) ...[
                const Text(
                  'Letzte Runs',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 110),
                  child: ListView.builder(
                    itemCount: _history.take(4).length,
                    itemBuilder: (context, idx) {
                      final rec = _history[idx];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              rec.dateString,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                            ),
                            Text(
                              '${rec.score} Pkt  (Streak: ${rec.bestStreak})',
                              style: const TextStyle(
                                color: Color(0xFFFFB74D),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Start Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB74D),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                ),
                onPressed: () {
                  final config = PuzzleRushConfig(
                    durationSeconds: _durationSeconds,
                    lives: _lives,
                    includeAntiTactics: _includeAntiTactics,
                    difficultyRampStep: _difficultyRampStep,
                  );
                  PuzzleRushStorage.saveConfig(config);
                  Navigator.of(context).pop();
                  widget.onStart(config);
                },
                child: const Text(
                  'Rush Starten 🚀',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFFFB74D)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFFB74D)
                  : Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
