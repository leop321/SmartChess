import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as prov;

import '../../../../logic/game_mode_notifier.dart';
import '../../../../model/app_model.dart';
import '../../../../model/app_themes.dart';

/// Segmented chip picker that selects between Normal, Blind, and Snapshot modes.
/// Uses Riverpod [gameModeProvider]; styled to match the existing [GameModePicker].
class ChessModePicker extends ConsumerWidget {
  const ChessModePicker({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = prov.Provider.of<AppModel>(context).theme;
    final selectedMode = ref.watch(gameModeProvider);
    final notifier = ref.read(gameModeProvider.notifier);

    final bgTop = theme.background?.colors.first ?? const Color(0xFF0A0F0C);
    final isDarkBg =
        ThemeData.estimateBrightnessForColor(bgTop) == Brightness.dark;
    final trackBgColor =
        isDarkBg ? const Color(0x660E0E0E) : const Color(0x1A000000);
    final trackBorderColor =
        isDarkBg ? const Color(0x14FFFFFF) : const Color(0x1F000000);
    final inactiveTextColor =
        isDarkBg ? const Color(0x99C3C8C2) : const Color(0x99313030);
    final primaryColor = theme.lightTile;
    final activeBgColor = theme.darkTile.withValues(alpha: 0.4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CHESS MODE',
          style: TextStyle(
            color: primaryColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Normal · Blind (no board) · Snapshot (frozen board)',
          style: TextStyle(
            color: primaryColor.withValues(alpha: 0.5),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: trackBgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: trackBorderColor, width: 1),
          ),
          child: Row(
            children: [
              _chip(
                context: context,
                label: 'Normal',
                icon: Icons.visibility_outlined,
                mode: ChessMode.normal,
                selected: selectedMode,
                theme: theme,
                primaryColor: primaryColor,
                activeBgColor: activeBgColor,
                inactiveTextColor: inactiveTextColor,
                onTap: () {
                  prov.Provider.of<AppModel>(context, listen: false)
                      .haptic
                      .light();
                  notifier.setMode(ChessMode.normal);
                },
              ),
              _chip(
                context: context,
                label: 'Blind',
                icon: Icons.visibility_off_outlined,
                mode: ChessMode.blind,
                selected: selectedMode,
                theme: theme,
                primaryColor: primaryColor,
                activeBgColor: activeBgColor,
                inactiveTextColor: inactiveTextColor,
                onTap: () {
                  prov.Provider.of<AppModel>(context, listen: false)
                      .haptic
                      .light();
                  notifier.setMode(ChessMode.blind);
                },
              ),
              _chip(
                context: context,
                label: 'Snapshot',
                icon: Icons.camera_alt_outlined,
                mode: ChessMode.snapshot,
                selected: selectedMode,
                theme: theme,
                primaryColor: primaryColor,
                activeBgColor: activeBgColor,
                inactiveTextColor: inactiveTextColor,
                onTap: () {
                  prov.Provider.of<AppModel>(context, listen: false)
                      .haptic
                      .light();
                  notifier.setMode(ChessMode.snapshot);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip({
    required BuildContext context,
    required String label,
    required IconData icon,
    required ChessMode mode,
    required ChessMode selected,
    required AppTheme theme,
    required Color primaryColor,
    required Color activeBgColor,
    required Color inactiveTextColor,
    required VoidCallback onTap,
  }) {
    final isSelected = mode == selected;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? activeBgColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? primaryColor : inactiveTextColor,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? primaryColor : inactiveTextColor,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
