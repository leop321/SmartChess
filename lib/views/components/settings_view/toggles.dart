import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../model/app_model.dart';
import '../shared/glass_panel.dart';
import 'toggle.dart';

class Toggles extends StatelessWidget {
  final AppModel appModel;

  const Toggles(this.appModel, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeColor =
        const Color(0x1A424843); // outline-variant/10 (0x1A is ~10% opacity)

    final platform = Theme.of(context).platform;
    final String achievementsSubtitle = 'Enables Google Play Games integration';

    final theme = appModel.theme;

    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Toggle(
            'Auto-Rotate Board (2P)',
            icon: Icons.sync,
            toggle: appModel.enableRotation,
            setFunc: appModel.setEnableRotation,
          ),
          Divider(height: 1, color: themeColor, thickness: 1),
          Toggle(
            'Auto-Rotate Pieces (2P)',
            icon: Icons.rotate_left_rounded,
            toggle:
                appModel.enableRotation ? false : appModel.enablePieceRotation,
            setFunc: appModel.setEnablePieceRotation,
            enabled: !appModel.enableRotation,
          ),
          Divider(height: 1, color: themeColor, thickness: 1),
          Toggle(
            'Move Hints & Highlights',
            icon: Icons.track_changes_rounded,
            toggle: appModel.showHints,
            setFunc: appModel.setShowHints,
          ),
          Divider(height: 1, color: themeColor, thickness: 1),
          Toggle(
            'Show Notation',
            icon: Icons.description_outlined,
            toggle: appModel.showNotation,
            setFunc: appModel.setShowNotation,
          ),
          Divider(height: 1, color: themeColor, thickness: 1),
          Toggle(
            'Allow Undo/Redo',
            icon: Icons.history_rounded,
            toggle: appModel.allowUndoRedo,
            setFunc: appModel.setAllowUndoRedo,
          ),
          Divider(height: 1, color: themeColor, thickness: 1),
          Toggle(
            'Show Move History',
            icon: Icons.list_alt_rounded,
            toggle: appModel.showMoveHistory,
            setFunc: appModel.setShowMoveHistory,
          ),
          Divider(height: 1, color: themeColor, thickness: 1),
          Toggle(
            'Sound',
            icon: Icons.volume_up_rounded,
            toggle: appModel.soundEnabled,
            setFunc: appModel.setSoundEnabled,
          ),
          Divider(height: 1, color: themeColor, thickness: 1),
          Toggle(
            'Haptic Feedback',
            icon: Icons.vibration_rounded,
            toggle: appModel.hapticEnabled,
            setFunc: appModel.setHapticEnabled,
          ),
          if (platform != TargetPlatform.iOS) ...[
            Divider(height: 1, color: themeColor, thickness: 1),
            _SettingsTile(
              label: 'Achievements',
              icon: Icons.sports_esports_outlined,
              subtitle: achievementsSubtitle,
              theme: theme,
              onTap: appModel.showAchievements,
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String label;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final dynamic
      theme; // Using dynamic to avoid explicit AppTheme import type casting issues if any, or just import/use it directly since it is in scope.

  const _SettingsTile({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.theme,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(
              icon,
              color: theme.lightTile,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFE5E2E1),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: const Color(0xFFC3C8C2).withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: const Color(0xFFC3C8C2).withValues(alpha: 0.5),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class TextToSpeechSettings extends StatelessWidget {
  final AppModel appModel;
  const TextToSpeechSettings(this.appModel, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeColor =
        const Color(0x1A424843); // outline-variant/10 (0x1A is ~10% opacity)
    final theme = appModel.theme;

    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Toggle(
            'Text-to-Speech',
            icon: Icons.record_voice_over_rounded,
            toggle: appModel.ttsEnabled,
            setFunc: appModel.setTtsEnabled,
          ),
          if (appModel.ttsEnabled) ...[
            Divider(height: 1, color: themeColor, thickness: 1),
            // Speech Rate Slider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.speed_rounded, color: theme.lightTile, size: 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Speech Speed: ${appModel.ttsSpeechRate.toStringAsFixed(1)}x",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFE5E2E1),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Slider(
                          value: appModel.ttsSpeechRate,
                          min: 0.1,
                          max: 1.0,
                          activeColor: theme.moveHint,
                          inactiveColor: theme.lightTile.withValues(alpha: 0.2),
                          onChanged: (val) => appModel.setTtsSpeechRate(val),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: themeColor, thickness: 1),
            // Speech Pitch Slider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.height_rounded, color: theme.lightTile, size: 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Speech Pitch: ${appModel.ttsPitch.toStringAsFixed(1)}",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFE5E2E1),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Slider(
                          value: appModel.ttsPitch,
                          min: 0.5,
                          max: 2.0,
                          activeColor: theme.moveHint,
                          inactiveColor: theme.lightTile.withValues(alpha: 0.2),
                          onChanged: (val) => appModel.setTtsPitch(val),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: theme.moveHint.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                onPressed: () {
                  appModel.haptic.light();
                  appModel.speak("Testing voice settings");
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded,
                        color: theme.lightTile, size: 20),
                    const SizedBox(width: 6),
                    Text(
                      'Test Voice',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.lightTile,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
