import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/lichess_puzzle.dart';
import 'components/shared/glass_panel.dart';

class TacticsSettingsView extends StatefulWidget {
  final int initialRatingOffset;
  final ValueChanged<int> onRatingOffsetChanged;

  const TacticsSettingsView({
    Key? key,
    required this.initialRatingOffset,
    required this.onRatingOffsetChanged,
  }) : super(key: key);

  @override
  State<TacticsSettingsView> createState() => _TacticsSettingsViewState();
}

class _TacticsSettingsViewState extends State<TacticsSettingsView> {
  bool _showHints = true;
  bool _autoNext = false;
  bool _showTimer = true;
  int _timePerPuzzle = 30;
  late int _ratingOffset;
  int _prefetchCount = 5;

  @override
  void initState() {
    super.initState();
    _ratingOffset = widget.initialRatingOffset;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final showTimer = await TacticsStorage.loadShowTimer();
    if (mounted) {
      setState(() {
        _showTimer = showTimer;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AppModel, AppTheme>(
      selector: (_, m) => m.theme,
      builder: (context, theme, child) {
        final accent = theme.lightTile;

        return Scaffold(
          body: Container(
            decoration: BoxDecoration(gradient: theme.background),
            child: SafeArea(
              child: Column(
                children: [
                  // ── Header Row ──
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.of(context).pop(),
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: theme.lightTile,
                            size: 22,
                          ),
                        ),
                        Text(
                          'Tactics Settings',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: theme.lightTile,
                          ),
                        ),
                        const SizedBox(
                            width: 44), // Spacer to balance back button
                      ],
                    ),
                  ),

                  // ── Main settings list ──
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20.0, vertical: 12.0),
                      physics: const BouncingScrollPhysics(),
                      children: [
                        GlassPanel(
                          borderRadius: 20,
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              // Puzzle Difficulty Offset
                              _PuzzleDifficultyRow(
                                accent: accent,
                                currentOffset: _ratingOffset,
                                onChanged: (v) {
                                  setState(() => _ratingOffset = v);
                                  widget.onRatingOffsetChanged(v);
                                },
                              ),
                              _SettingsDivider(accent: accent),

                              // Prefetch Count
                              _PrefetchCountRow(
                                accent: accent,
                                currentCount: _prefetchCount,
                                onChanged: (v) {
                                  setState(() => _prefetchCount = v);
                                },
                              ),
                              _SettingsDivider(accent: accent),

                              // Show Move Hints
                              _SettingsToggleRow(
                                icon: Icons.lightbulb_outline_rounded,
                                label: 'Show Move Hints',
                                subtitle: 'Highlight possible target squares',
                                value: _showHints,
                                accent: accent,
                                onChanged: (v) =>
                                    setState(() => _showHints = v),
                              ),
                              _SettingsDivider(accent: accent),

                              // Auto Advance
                              _SettingsToggleRow(
                                icon: Icons.skip_next_rounded,
                                label: 'Auto-Advance',
                                subtitle: 'Proceed automatically after solving',
                                value: _autoNext,
                                accent: accent,
                                onChanged: (v) => setState(() => _autoNext = v),
                              ),
                              _SettingsDivider(accent: accent),

                              // Show Timer
                              _SettingsToggleRow(
                                icon: Icons.timer_outlined,
                                label: 'Show Timer',
                                subtitle: 'Display elapsed time per puzzle',
                                value: _showTimer,
                                accent: accent,
                                onChanged: (v) {
                                  setState(() => _showTimer = v);
                                  TacticsStorage.saveShowTimer(v);
                                },
                              ),
                              _SettingsDivider(accent: accent),

                              // Time Limit
                              _SettingsStepperRow(
                                icon: Icons.hourglass_bottom_rounded,
                                label: 'Time Limit',
                                subtitle:
                                    'Seconds allowed per puzzle (0 = unlimited)',
                                value: _timePerPuzzle,
                                min: 0,
                                max: 300,
                                step: 15,
                                formatValue: (v) => v == 0 ? '∞' : '${v}s',
                                accent: accent,
                                onChanged: (v) =>
                                    setState(() => _timePerPuzzle = v),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Shared UI helper components inside settings ──

class _SettingsDivider extends StatelessWidget {
  final Color accent;
  const _SettingsDivider({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      height: 0.5,
      color: const Color(0xFFFFFFFF).withValues(alpha: 0.07),
    );
  }
}

class _SettingsToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  const _SettingsToggleRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: accent.withValues(alpha: value ? 0.12 : 0.05),
          ),
          child: Center(
            child: Icon(
              icon,
              color: value
                  ? accent
                  : const Color(0xFFE5E2E1).withValues(alpha: 0.35),
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE5E2E1),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: const Color(0xFFE5E2E1).withValues(alpha: 0.38),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        CupertinoSwitch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: accent,
        ),
      ],
    );
  }
}

class _SettingsStepperRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final int value;
  final int min;
  final int max;
  final int step;
  final String Function(int) formatValue;
  final Color accent;
  final ValueChanged<int> onChanged;

  const _SettingsStepperRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.formatValue,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: accent.withValues(alpha: 0.08),
          ),
          child: Center(
            child: Icon(
              icon,
              color: const Color(0xFFE5E2E1).withValues(alpha: 0.50),
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE5E2E1),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: const Color(0xFFE5E2E1).withValues(alpha: 0.38),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepperButton(
              icon: Icons.remove_rounded,
              onTap: value > min
                  ? () => onChanged((value - step).clamp(min, max))
                  : null,
              accent: accent,
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 40),
              alignment: Alignment.center,
              child: Text(
                formatValue(value),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
            _StepperButton(
              icon: Icons.add_rounded,
              onTap: value < max
                  ? () => onChanged((value + step).clamp(min, max))
                  : null,
              accent: accent,
            ),
          ],
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color accent;

  const _StepperButton({
    required this.icon,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: onTap != null
              ? accent.withValues(alpha: 0.12)
              : const Color(0xFFFFFFFF).withValues(alpha: 0.04),
          border: Border.all(
            color: onTap != null
                ? accent.withValues(alpha: 0.28)
                : const Color(0xFFFFFFFF).withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          size: 14,
          color: onTap != null
              ? accent
              : const Color(0xFFE5E2E1).withValues(alpha: 0.22),
        ),
      ),
    );
  }
}

const _kOffsetOptions = [-300, -150, 0, 150, 300];

class _PuzzleDifficultyRow extends StatelessWidget {
  final Color accent;
  final int currentOffset;
  final ValueChanged<int> onChanged;

  const _PuzzleDifficultyRow({
    required this.accent,
    required this.currentOffset,
    required this.onChanged,
  });

  String _label(int offset) {
    if (offset == 0) return 'Matched';
    if (offset < 0) return 'Easier';
    return 'Harder';
  }

  String _offsetLabel(int offset) {
    if (offset == 0) return '±0 ELO';
    if (offset < 0) return '${offset} ELO';
    return '+$offset ELO';
  }

  Color _chipColor(int offset) {
    if (offset == 0) return accent;
    if (offset < 0) return const Color(0xFF4FC3F7);
    return const Color(0xFFEF7090);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: accent.withValues(alpha: 0.08),
              ),
              child: Center(
                child: Icon(
                  Icons.equalizer_rounded,
                  color: const Color(0xFFE5E2E1).withValues(alpha: 0.55),
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Puzzle Difficulty',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE5E2E1),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Puzzle rating relative to your tactics rating',
                    style: TextStyle(
                      fontSize: 11,
                      color: const Color(0xFFE5E2E1).withValues(alpha: 0.38),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              ..._kOffsetOptions.map((offset) {
                final isActive = currentOffset == offset;
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: _buildChip(offset, isActive, _label(offset),
                      _offsetLabel(offset), _chipColor(offset)),
                );
              }),
              if (!_kOffsetOptions.contains(currentOffset))
                Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: _buildChip(currentOffset, true, 'Custom',
                      _offsetLabel(currentOffset), _chipColor(currentOffset)),
                ),
              _buildCustomButton(context, 'Custom Offset', true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChip(int value, bool isActive, String label, String subLabel,
      Color chipColor) {
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isActive
              ? chipColor.withValues(alpha: 0.18)
              : const Color(0xFFFFFFFF).withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? chipColor.withValues(alpha: 0.50)
                : const Color(0xFFFFFFFF).withValues(alpha: 0.07),
            width: isActive ? 1.5 : 1.0,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: chipColor.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? chipColor
                    : const Color(0xFFE5E2E1).withValues(alpha: 0.45),
                letterSpacing: 0.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subLabel,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: isActive
                    ? chipColor.withValues(alpha: 0.85)
                    : const Color(0xFFE5E2E1).withValues(alpha: 0.28),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomButton(
      BuildContext context, String title, bool allowNegative) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () {
        final controller =
            TextEditingController(text: currentOffset.toString());
        showCupertinoDialog(
          context: context,
          builder: (context) {
            return CupertinoAlertDialog(
              title: Text(title),
              content: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: CupertinoTextField(
                  controller: controller,
                  keyboardType:
                      TextInputType.numberWithOptions(signed: allowNegative),
                  placeholder: 'Enter a value',
                  autofocus: true,
                ),
              ),
              actions: [
                CupertinoDialogAction(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.pop(context),
                ),
                CupertinoDialogAction(
                  child: const Text('Save'),
                  onPressed: () {
                    final val = int.tryParse(controller.text);
                    if (val != null) {
                      onChanged(val);
                    }
                    Navigator.pop(context);
                  },
                ),
              ],
            );
          },
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.07),
            width: 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded,
                color: accent.withValues(alpha: 0.8), size: 16),
            const SizedBox(height: 2),
            Text(
              'Custom',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFE5E2E1).withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _kPrefetchOptions = [0, 5, 10, 20];

class _PrefetchCountRow extends StatelessWidget {
  final Color accent;
  final int currentCount;
  final ValueChanged<int> onChanged;

  const _PrefetchCountRow({
    required this.accent,
    required this.currentCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: accent.withValues(alpha: 0.08),
              ),
              child: Center(
                child: Icon(
                  Icons.download_rounded,
                  color: const Color(0xFFE5E2E1).withValues(alpha: 0.55),
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Offline Prefetch',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE5E2E1),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Puzzles downloaded on close for offline play',
                    style: TextStyle(
                      fontSize: 11,
                      color: const Color(0xFFE5E2E1).withValues(alpha: 0.38),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              ..._kPrefetchOptions.map((count) {
                final isActive = currentCount == count;
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: _buildChip(count, isActive,
                      count == 0 ? 'None' : '$count', 'Puzzles'),
                );
              }),
              if (!_kPrefetchOptions.contains(currentCount))
                Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: _buildChip(
                      currentCount, true, '$currentCount', 'Puzzles'),
                ),
              _buildCustomButton(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChip(int value, bool isActive, String label, String subLabel) {
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          color: isActive
              ? accent.withValues(alpha: 0.18)
              : const Color(0xFFFFFFFF).withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? accent.withValues(alpha: 0.50)
                : const Color(0xFFFFFFFF).withValues(alpha: 0.07),
            width: isActive ? 1.5 : 1.0,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? accent
                    : const Color(0xFFE5E2E1).withValues(alpha: 0.45),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              subLabel,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: isActive
                    ? accent.withValues(alpha: 0.85)
                    : const Color(0xFFE5E2E1).withValues(alpha: 0.28),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomButton(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () {
        final controller = TextEditingController(text: currentCount.toString());
        showCupertinoDialog(
          context: context,
          builder: (context) {
            return CupertinoAlertDialog(
              title: const Text('Custom Count'),
              content: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: CupertinoTextField(
                  controller: controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(signed: false),
                  placeholder: 'Enter amount',
                  autofocus: true,
                ),
              ),
              actions: [
                CupertinoDialogAction(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.pop(context),
                ),
                CupertinoDialogAction(
                  child: const Text('Save'),
                  onPressed: () {
                    final val = int.tryParse(controller.text);
                    if (val != null && val >= 0) {
                      onChanged(val);
                    }
                    Navigator.pop(context);
                  },
                ),
              ],
            );
          },
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.07),
            width: 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded,
                color: accent.withValues(alpha: 0.8), size: 16),
            const SizedBox(height: 2),
            Text(
              'Custom',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFE5E2E1).withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
