import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../model/app_model.dart';

class AIDifficultyPicker extends StatefulWidget {
  final int aiDifficulty;
  final Function(int?) setFunc;

  const AIDifficultyPicker(this.aiDifficulty, this.setFunc, {Key? key})
      : super(key: key);

  @override
  State<AIDifficultyPicker> createState() => _AIDifficultyPickerState();
}

class _AIDifficultyPickerState extends State<AIDifficultyPicker> {
  /// The standard ELO tiers always shown.
  static const List<int> _baseElos = [400, 800, 1200, 1600, 2000];

  /// Maps a level (1-5) to its ELO, or returns the value directly if it's > 5
  /// (meaning it IS already an ELO).
  static int _levelToElo(int level) {
    if (level > 5) return level; // already an ELO value
    const map = {1: 400, 2: 800, 3: 1200, 4: 1600, 5: 2000};
    return map[level] ?? 1200;
  }

  /// Maps an ELO to the nearest level (1-5) for Stockfish.
  /// ELOs > 2000 map to level 5. Any non-standard ELO is stored directly
  /// (> 5 sentinel) and getDifficultyElo passes it through.
  static int _eloToLevel(int elo) {
    if (elo <= 400) return 1;
    if (elo <= 800) return 2;
    if (elo <= 1200) return 3;
    if (elo <= 1600) return 4;
    if (elo <= 2000) return 5;
    // For custom ELOs above 2000, store as-is (> 5 sentinel)
    return elo;
  }

  /// Builds the dynamic list of ELO values to show.
  List<int> _buildEloList(AppModel appModel) {
    final beatenLevels = appModel.prefs.beatenBots;
    final beatenElos = beatenLevels.map(_levelToElo).toList();

    // Find highest beaten ELO and compute +200, +400 steps
    final extraElos = <int>{};
    if (beatenElos.isNotEmpty) {
      final maxBeaten = beatenElos.reduce((a, b) => a > b ? a : b);
      // Add 2 steps above the highest beaten ELO in 200-ELO increments
      final next1 = maxBeaten + 200;
      final next2 = maxBeaten + 400;
      if (next1 <= 3200) extraElos.add(next1);
      if (next2 <= 3200) extraElos.add(next2);
    }

    // Merge base + extras, remove duplicates, sort
    final allElos = <int>{..._baseElos, ...extraElos}.toList()..sort();
    return allElos;
  }

  void _showCustomEloDialog(BuildContext context, AppModel appModel) {
    final controller = TextEditingController();
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Custom ELO'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            placeholder: '200 – 3200',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Set'),
            onPressed: () {
              final val = int.tryParse(controller.text);
              if (val != null && val >= 200 && val <= 3200) {
                widget.setFunc(_eloToLevel(val));
                Navigator.of(ctx).pop();
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appModel = Provider.of<AppModel>(context);
    final theme = appModel.theme;
    final primaryColor = theme.lightTile;
    final badgeColor = theme.moveHint.withValues(alpha: 1.0);
    final badgeBgColor = theme.moveHint.withValues(alpha: 0.12);

    final bgTop = theme.background?.colors.first ?? const Color(0xFF0A0F0C);
    final isDarkBg =
        ThemeData.estimateBrightnessForColor(bgTop) == Brightness.dark;

    final inactiveTextColor =
        isDarkBg ? const Color(0x99C3C8C2) : const Color(0x99313030);

    final currentElo = _levelToElo(widget.aiDifficulty);
    final eloList = _buildEloList(appModel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'AI DIFFICULTY',
              style: TextStyle(
                color: primaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badgeBgColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$currentElo ELO',
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // ELO pill row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              ...eloList.map((elo) {
                final isSelected = currentElo == elo;
                return GestureDetector(
                  onTap: () => widget.setFunc(_eloToLevel(elo)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.moveHint.withValues(alpha: 0.2)
                          : theme.darkTile.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? theme.moveHint.withValues(alpha: 0.7)
                            : theme.lightTile.withValues(alpha: 0.15),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Text(
                      '$elo',
                      style: TextStyle(
                        color: isSelected ? theme.moveHint : inactiveTextColor,
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }),
              // Custom ELO "+" button
              GestureDetector(
                onTap: () => _showCustomEloDialog(context, appModel),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.darkTile.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.lightTile.withValues(alpha: 0.15),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_rounded,
                          size: 13, color: inactiveTextColor),
                      const SizedBox(width: 4),
                      Text(
                        'Custom',
                        style: TextStyle(
                          color: inactiveTextColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
