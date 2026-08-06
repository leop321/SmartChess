import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/puzzle_rush_storage.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/lichess_puzzle.dart';
import '../model/tactics_task.dart';
import 'components/shared/glass_panel.dart';
import 'components/tactics_view/puzzle_rush_settings_dialog.dart';
import 'tactics_puzzle_view.dart';
import 'tactics_settings_view.dart';

// ── Shared DotGridPainter ──
class DotGridPainter extends CustomPainter {
  final Color color;
  const DotGridPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;
    const spacing = 20.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Tactics Mode Info Extension
// ─────────────────────────────────────────────────────

extension TacticsModeInfo on TacticsMode {
  String get title {
    switch (this) {
      case TacticsMode.classic:
        return 'Tactics';
      case TacticsMode.puzzleRush:
        return 'Puzzle Rush';
      case TacticsMode.antiTactics:
        return 'Anti-Tactics';
      case TacticsMode.antiTacticsV2:
        return 'Anti-Tactics V2';
      case TacticsMode.blindfold:
        return 'Blindfold';
    }
  }

  String get subtitle {
    switch (this) {
      case TacticsMode.classic:
        return 'Solve puzzles at your own pace';
      case TacticsMode.puzzleRush:
        return 'Beat the clock — how many can you solve?';
      case TacticsMode.antiTactics:
        return 'Finde Fake-Taktiken und spiele auf Sicherheit.';
      case TacticsMode.antiTacticsV2:
        return 'Erkenne Taktik-lose Situationen aus besten Zügen.';
      case TacticsMode.blindfold:
        return 'No board shown — pure visualization';
    }
  }

  IconData get icon {
    switch (this) {
      case TacticsMode.classic:
        return Icons.extension_rounded;
      case TacticsMode.puzzleRush:
        return Icons.bolt_rounded;
      case TacticsMode.antiTactics:
        return Icons.security_rounded;
      case TacticsMode.antiTacticsV2:
        return Icons.shield_moon_rounded;
      case TacticsMode.blindfold:
        return Icons.visibility_off_rounded;
    }
  }

  Color get accentColor {
    switch (this) {
      case TacticsMode.classic:
        return const Color(0xFF7AB8F5);
      case TacticsMode.puzzleRush:
        return const Color(0xFFFFB74D);
      case TacticsMode.antiTactics:
        return const Color(0xFFEF7090);
      case TacticsMode.antiTacticsV2:
        return const Color(0xFFEF7090);
      case TacticsMode.blindfold:
        return const Color(0xFFB39DDB);
    }
  }

  String get tag {
    switch (this) {
      case TacticsMode.classic:
        return '';
      case TacticsMode.puzzleRush:
        return 'TIMED';
      case TacticsMode.antiTactics:
        return 'TRICKY';
      case TacticsMode.antiTacticsV2:
        return 'TRICKY V2';
      case TacticsMode.blindfold:
        return 'HARD';
    }
  }
}

// ─────────────────────────────────────────────────────
// Main TacticsView
// ─────────────────────────────────────────────────────

class TacticsView extends StatefulWidget {
  const TacticsView({Key? key}) : super(key: key);

  @override
  State<TacticsView> createState() => _TacticsViewState();
}

class _TacticsViewState extends State<TacticsView> {
  TacticsMode _selectedMode = TacticsMode.classic;
  int _ratingOffset = 0;

  @override
  void initState() {
    super.initState();
    _loadRatingOffset();
  }

  Future<void> _loadRatingOffset() async {
    final offset = await TacticsStorage.loadRatingOffset();
    if (mounted) {
      setState(() {
        _ratingOffset = offset;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AppModel, AppTheme>(
      selector: (_, m) => m.theme,
      builder: (context, theme, child) {
        return Scaffold(
          body: Container(
            decoration: BoxDecoration(gradient: theme.background),
            child: Stack(
              children: [
                // Dot grid background
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: DotGridPainter(
                        color: theme.lightTile.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                ),

                // Ambient glow top-left
                Positioned(
                  top: -40,
                  left: -60,
                  child: RepaintBoundary(
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: theme.lightTile.withValues(alpha: 0.07),
                            blurRadius: 130,
                            spreadRadius: 40,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Ambient glow bottom-right
                Positioned(
                  bottom: -60,
                  right: -40,
                  child: RepaintBoundary(
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _selectedMode.accentColor
                                .withValues(alpha: 0.06),
                            blurRadius: 120,
                            spreadRadius: 30,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Main scrollable content
                SafeArea(
                  bottom: false,
                  child: Consumer<AppModel>(
                    builder: (context, appModel, _) {
                      return ListView(
                        padding: const EdgeInsets.only(
                          left: 20,
                          right: 20,
                          bottom: 120,
                        ),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          const SizedBox(height: 16),

                          // ── Header ──
                          _TacticsHeader(
                            theme: theme,
                            ratingOffset: _ratingOffset,
                            onRatingOffsetChanged: (v) {
                              setState(() => _ratingOffset = v);
                              TacticsStorage.saveRatingOffset(v);
                            },
                          ),
                          const SizedBox(height: 20),

                          // ── Rating Cards ──
                          _TacticsRatingRow(
                              appModel: appModel,
                              theme: theme,
                              mode: _selectedMode),
                          const SizedBox(height: 24),

                          // ── Mode Selection Label ──
                          _SectionLabel(
                            label: 'SELECT MODE',
                            theme: theme,
                          ),
                          const SizedBox(height: 12),

                          // ── Mode Cards ──
                          ...TacticsMode.values.map(
                            (mode) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _ModeCard(
                                mode: mode,
                                isSelected: _selectedMode == mode,
                                theme: theme,
                                onTap: () {
                                  appModel.haptic.light();
                                  setState(() => _selectedMode = mode);
                                },
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),

                          // ── Start Button ──
                          _StartButton(
                            mode: _selectedMode,
                            theme: theme,
                            appModel: appModel,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────

class _TacticsHeader extends StatelessWidget {
  final AppTheme theme;
  final int ratingOffset;
  final ValueChanged<int> onRatingOffsetChanged;

  const _TacticsHeader({
    required this.theme,
    required this.ratingOffset,
    required this.onRatingOffsetChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tactics',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFE5E2E1),
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Sharpen your chess mind',
                style: TextStyle(
                  fontSize: 13,
                  color: const Color(0xFFE5E2E1).withValues(alpha: 0.45),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        // Settings gear button
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            Navigator.of(context).push(
              CupertinoPageRoute(
                builder: (context) => TacticsSettingsView(
                  initialRatingOffset: ratingOffset,
                  onRatingOffsetChanged: onRatingOffsetChanged,
                ),
              ),
            );
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.lightTile.withValues(alpha: 0.10),
              border: Border.all(
                color: theme.lightTile.withValues(alpha: 0.22),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.settings_rounded,
                color: theme.lightTile,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────
// Tactics Rating Row (Tactics + Blitz Rush ratings)
// ─────────────────────────────────────────────────────

class _TacticsRatingRow extends StatelessWidget {
  final AppModel appModel;
  final AppTheme theme;
  final TacticsMode mode;
  const _TacticsRatingRow({
    required this.appModel,
    required this.theme,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(int, int)>(
      future: _loadRatingAndLastChange(),
      builder: (context, snapshot) {
        final rating = snapshot.data?.$1 ?? 1200;
        final lastChange = snapshot.data?.$2 ?? 0;
        return Row(
          children: [
            Expanded(
              child: _TacticsRatingCard(
                label: mode.title.toUpperCase(),
                rating: rating,
                lastChange: lastChange,
                accentColor: mode.accentColor,
                theme: theme,
                icon: mode.icon,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TacticsRatingCard(
                label: 'BLITZ RUSH',
                rating: 0,
                lastChange: 0,
                accentColor: TacticsMode.puzzleRush.accentColor,
                theme: theme,
                icon: Icons.bolt_rounded,
                isHighScore: true,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<(int, int)> _loadRatingAndLastChange() async {
    final ratingKey = mode == TacticsMode.puzzleRush ? 'classic' : mode.name;
    final rating = await TacticsStorage.loadRating(mode: ratingKey);
    final history = await TacticsStorage.loadHistory(mode: ratingKey);
    final lastChange = history.isNotEmpty ? history.first.ratingChange : 0;
    return (rating, lastChange);
  }
}

class _TacticsRatingCard extends StatelessWidget {
  final String label;
  final int rating;
  final int lastChange;
  final Color accentColor;
  final AppTheme theme;
  final IconData icon;
  final bool isHighScore;

  const _TacticsRatingCard({
    required this.label,
    required this.rating,
    required this.lastChange,
    required this.accentColor,
    required this.theme,
    required this.icon,
    this.isHighScore = false,
  });

  @override
  Widget build(BuildContext context) {
    final (nextMilestone, prevMilestone) =
        _milestones(isHighScore ? 0 : rating);
    final progress = isHighScore
        ? 0.0
        : (rating - prevMilestone) / (nextMilestone - prevMilestone);

    return GlassPanel(
      borderRadius: 16,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accentColor, size: 12),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: accentColor.withValues(alpha: 0.85),
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                isHighScore ? '—' : '$rating',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFE5E2E1),
                  letterSpacing: -1,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              if (lastChange != 0 && !isHighScore)
                _ChangeIndicator(change: lastChange),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isHighScore ? 'Best Score' : _rankTitle(rating),
            style: TextStyle(
              fontSize: 12,
              color: accentColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (!isHighScore) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$prevMilestone',
                  style: TextStyle(
                    fontSize: 9,
                    color: const Color(0xFFE5E2E1).withValues(alpha: 0.35),
                  ),
                ),
                Text(
                  '$nextMilestone',
                  style: TextStyle(
                    fontSize: 9,
                    color: const Color(0xFFE5E2E1).withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: accentColor.withValues(alpha: 0.10),
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                minHeight: 4,
              ),
            ),
          ] else ...[
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _rankTitle(int r) {
    if (r < 600) return 'Beginner';
    if (r < 1000) return 'Casual';
    if (r < 1400) return 'Intermediate';
    if (r < 1800) return 'Advanced';
    return 'Master';
  }

  (int, int) _milestones(int r) {
    const milestones = [0, 600, 1000, 1400, 1800, 3200];
    for (int i = 0; i < milestones.length - 1; i++) {
      if (r < milestones[i + 1]) return (milestones[i + 1], milestones[i]);
    }
    return (3200, 1800);
  }
}

class _ChangeIndicator extends StatelessWidget {
  final int change;
  const _ChangeIndicator({required this.change});

  @override
  Widget build(BuildContext context) {
    final isPositive = change > 0;
    final color =
        isPositive ? const Color(0xFF4CAF50) : const Color(0xFFFF5252);
    final sign = isPositive ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        '$sign$change',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// Section Label
// ─────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final AppTheme theme;
  const _SectionLabel({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: theme.lightTile.withValues(alpha: 0.55),
        letterSpacing: 2.0,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// Mode Card
// ─────────────────────────────────────────────────────

class _ModeCard extends StatelessWidget {
  final TacticsMode mode;
  final bool isSelected;
  final AppTheme theme;
  final VoidCallback onTap;

  const _ModeCard({
    required this.mode,
    required this.isSelected,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = mode.accentColor;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? accent.withValues(alpha: 0.55)
                : const Color(0xFFFFFFFF).withValues(alpha: 0.06),
            width: isSelected ? 1.5 : 1.0,
          ),
          color: isSelected
              ? accent.withValues(alpha: 0.08)
              : const Color(0xFF201F1F).withValues(alpha: 0.40),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.12),
                    blurRadius: 20,
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Icon container
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: isSelected
                    ? accent.withValues(alpha: 0.18)
                    : const Color(0xFFFFFFFF).withValues(alpha: 0.05),
                border: Border.all(
                  color: isSelected
                      ? accent.withValues(alpha: 0.40)
                      : const Color(0xFFFFFFFF).withValues(alpha: 0.06),
                  width: 1.0,
                ),
              ),
              child: Center(
                child: Icon(
                  mode.icon,
                  color: isSelected
                      ? accent
                      : const Color(0xFFE5E2E1).withValues(alpha: 0.35),
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Text info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        mode.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? const Color(0xFFE5E2E1)
                              : const Color(0xFFE5E2E1).withValues(alpha: 0.65),
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (mode.tag.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            mode.tag,
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: accent,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    mode.subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFFE5E2E1).withValues(alpha: 0.38),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // Selection indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? accent : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? accent
                      : const Color(0xFFFFFFFF).withValues(alpha: 0.18),
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Center(
                      child: Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 13,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// Start Button
// ─────────────────────────────────────────────────────

class _StartButton extends StatelessWidget {
  final TacticsMode mode;
  final AppTheme theme;
  final AppModel appModel;

  const _StartButton({
    required this.mode,
    required this.theme,
    required this.appModel,
  });

  @override
  Widget build(BuildContext context) {
    final accent = mode.accentColor;

    return Container(
      width: double.infinity,
      height: 62,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.90),
            accent.withValues(alpha: 0.65),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () async {
          appModel.haptic.light();
          if (mode == TacticsMode.puzzleRush) {
            final currentConfig = await PuzzleRushStorage.loadConfig();
            if (!context.mounted) return;
            showDialog(
              context: context,
              builder: (ctx) => PuzzleRushSettingsDialog(
                initialConfig: currentConfig,
                onStart: (config) {
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (context) => TacticsPuzzleView(
                        mode: TacticsMode.puzzleRush,
                      ),
                    ),
                  );
                },
              ),
            );
          } else if (mode == TacticsMode.classic ||
              mode == TacticsMode.antiTactics ||
              mode == TacticsMode.antiTacticsV2) {
            Navigator.of(context).push(
              CupertinoPageRoute(
                builder: (context) => TacticsPuzzleView(mode: mode),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${mode.title} mode is coming soon!'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              mode.icon,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              'START ${mode.title.toUpperCase()}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
