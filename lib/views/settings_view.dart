import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/game_mode_notifier.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import 'components/settings_view/app_theme_picker.dart';
import 'components/settings_view/linked_accounts_section.dart';
import 'components/settings_view/piece_theme_picker.dart';
import 'components/settings_view/toggles.dart';
import 'components/shared/bottom_padding.dart';
import 'components/shared/glass_panel.dart';

class SettingsView extends StatefulWidget {
  final bool isTab;
  const SettingsView({Key? key, this.isTab = false}) : super(key: key);

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showResetConfirmation(BuildContext context, AppModel appModel) {
    showGeneralDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, anim1, anim2) {
        return Selector<AppModel, AppTheme>(
          selector: (_, m) => m.theme,
          builder: (dialogContext, theme, child) => Center(
            child: Material(
              color: Colors.transparent,
              child: GlassPanel(
                borderRadius: 24,
                padding: const EdgeInsets.all(20),
                color: const Color(0x80201F1F),
                animation: anim1,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Reset Settings',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE5E2E1),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Are you sure you want to reset all settings to their defaults?',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFFC3C8C2),
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          // Cancel Button
                          Expanded(
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => Navigator.pop(dialogContext),
                              child: Container(
                                height: 46,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    width: 1,
                                  ),
                                ),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFC3C8C2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Reset Button
                          Expanded(
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                appModel.resetSettingsToDefaults();
                              },
                              child: Container(
                                height: 46,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F0),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x33000000),
                                      blurRadius: 6,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  'Reset',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E211F),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1.drive(
            CurveTween(curve: Curves.easeOut),
          ),
          child: child,
        );
      },
    );
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
                // 1. Dot Grid Background
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: DotGridPainter(
                        color: theme.lightTile.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                ),

                // 2. Glowing Blur Backgrounds
                Positioned(
                  top: 150,
                  right: -50,
                  child: RepaintBoundary(
                    child: Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: theme.lightTile.withValues(alpha: 0.05),
                            blurRadius: 120,
                            spreadRadius: 30,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. Scrollable Content
                Positioned.fill(
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        // Glassy App Bar
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (!widget.isTab)
                                CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: () => Navigator.pop(context),
                                  child: Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    color: theme.lightTile,
                                    size: 22,
                                  ),
                                )
                              else
                                const SizedBox(width: 44),
                              GestureDetector(
                                onTap: () {
                                  if (_scrollController.hasClients) {
                                    _scrollController.animateTo(
                                      0,
                                      duration:
                                          const Duration(milliseconds: 300),
                                      curve: Curves.easeOut,
                                    );
                                  }
                                },
                                behavior: HitTestBehavior.opaque,
                                child: const Text(
                                  'Settings',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFE5E2E1),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              Consumer<AppModel>(
                                builder: (context, appModel, child) =>
                                    CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: () =>
                                      _showResetConfirmation(context, appModel),
                                  child: Icon(
                                    Icons.refresh_rounded,
                                    color: theme.lightTile,
                                    size: 26,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 16),
                            physics: const BouncingScrollPhysics(),
                            children: [
                              const AppThemePicker(),
                              const SizedBox(height: 24),
                              const PieceThemePicker(),
                              const SizedBox(height: 24),
                              Consumer<AppModel>(
                                builder: (context, appModel, child) => Column(
                                  children: [
                                    RatingAdjustmentTile(appModel: appModel),
                                    const SizedBox(height: 24),
                                    Toggles(appModel),
                                    const SizedBox(height: 24),
                                    TextToSpeechSettings(appModel),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              // ── Linked Accounts ──────────────────────
                              const LinkedAccountsSection(),
                              const SizedBox(height: 32),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'Made with ',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFC3C8C2),
                                    ),
                                  ),
                                  Icon(
                                    Icons.favorite_rounded,
                                    color: theme.lightTile,
                                    size: 13,
                                  ),
                                  const Text(
                                    ' by Paras Shenmare',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFC3C8C2),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              BottomPadding(),
                            ],
                          ),
                        ),
                      ],
                    ),
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

class RatingAdjustmentTile extends StatelessWidget {
  final AppModel appModel;
  const RatingAdjustmentTile({Key? key, required this.appModel})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = appModel.theme;
    final isBlind = appModel.gameMode == ChessMode.blind ||
        appModel.gameMode == ChessMode.snapshot;
    final isLocked = appModel.isRatingAdjustmentLocked(isBlind);
    final count = appModel.getRatingAdjustmentsCount(isBlind);
    final cooldownDays = appModel.getRatingAdjustmentCooldownDaysLeft(isBlind);

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isBlind
                ? 'MANUAL BLIND RATING ADJUSTMENT'
                : 'MANUAL RATING ADJUSTMENT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: theme.lightTile.withValues(alpha: 0.6),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rating: ${appModel.userRating} Elo',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE5E2E1),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isLocked
                        ? 'Cooldown: $cooldownDays days remaining'
                        : 'Changes used: $count/2',
                    style: TextStyle(
                      fontSize: 12,
                      color: isLocked
                          ? const Color(0xFFFF5252)
                          : const Color(0xFFC3C8C2).withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: isLocked
                    ? Colors.white.withValues(alpha: 0.05)
                    : theme.moveHint.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                onPressed: () {
                  appModel.haptic.light();
                  if (isLocked) {
                    _showCooldownAlert(context, cooldownDays, theme);
                  } else {
                    _showWarningDialog(context, appModel, count, theme);
                  }
                },
                child: Text(
                  isLocked ? 'Locked' : 'Adjust',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isLocked
                        ? const Color(0xFFE5E2E1).withValues(alpha: 0.3)
                        : theme.lightTile,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCooldownAlert(BuildContext context, int daysLeft, AppTheme theme) {
    showGeneralDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: GlassPanel(
              borderRadius: 24,
              padding: const EdgeInsets.all(20),
              color: const Color(0x80201F1F),
              animation: anim1,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_clock_rounded,
                        color: Color(0xFFFF5252), size: 36),
                    const SizedBox(height: 12),
                    const Text(
                      'Cooldown Active',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE5E2E1),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You have reached the maximum of 2 manual rating changes. Cooldown is active for $daysLeft more days.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFFC3C8C2),
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.moveHint.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'OK',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: theme.lightTile,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showWarningDialog(
      BuildContext context, AppModel appModel, int count, AppTheme theme) {
    showGeneralDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: GlassPanel(
              borderRadius: 24,
              padding: const EdgeInsets.all(20),
              color: const Color(0x80201F1F),
              animation: anim1,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.orangeAccent, size: 38),
                    const SizedBox(height: 12),
                    const Text(
                      'Rating Warning',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE5E2E1),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You can only manually adjust your rating 2 times. After that, a 60-day cooldown is enforced.\n\nChanges used: $count/2.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFFC3C8C2),
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.pop(dialogContext),
                            child: Container(
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFC3C8C2),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              Navigator.pop(dialogContext);
                              _showInputDialog(context, appModel, theme);
                            },
                            child: Container(
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: theme.moveHint,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Proceed',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showInputDialog(
      BuildContext context, AppModel appModel, AppTheme theme) {
    final controller =
        TextEditingController(text: appModel.userRating.toString());

    showGeneralDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: GlassPanel(
              borderRadius: 24,
              padding: const EdgeInsets.all(20),
              color: const Color(0x80201F1F),
              animation: anim1,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter New Rating',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE5E2E1),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1C).withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.lightTile.withValues(alpha: 0.2),
                        ),
                      ),
                      child: CupertinoTextField(
                        controller: controller,
                        style: const TextStyle(
                          color: Color(0xFFE5E2E1),
                          fontSize: 16,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: null,
                        keyboardType: TextInputType.number,
                        placeholder: 'Rating (100 - 3200)',
                        placeholderStyle: TextStyle(
                            color:
                                const Color(0xFFE5E2E1).withValues(alpha: 0.3)),
                        cursorColor: theme.lightTile,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.pop(dialogContext),
                            child: Container(
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFC3C8C2),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () async {
                              final text = controller.text.trim();
                              final val = int.tryParse(text);
                              if (val != null && val >= 100 && val <= 3200) {
                                final isBlind =
                                    appModel.gameMode == ChessMode.blind ||
                                        appModel.gameMode == ChessMode.snapshot;
                                await appModel.adjustUserRating(val, isBlind);
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                              } else {
                                // invalid input haptic
                                appModel.haptic.warning();
                              }
                            },
                            child: Container(
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: theme.moveHint,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Save',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
