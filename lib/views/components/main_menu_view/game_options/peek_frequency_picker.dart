import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as prov;
import '../../../../logic/peeking_notifier.dart';
import '../../../../model/app_model.dart';
import '../../shared/glass_panel.dart';

class PeekFrequencyPicker extends ConsumerWidget {
  const PeekFrequencyPicker({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = prov.Provider.of<AppModel>(context).theme;
    final peekState = ref.watch(peekingProvider);
    final notifier = ref.read(peekingProvider.notifier);

    final primaryColor = theme.lightTile;
    final activeBgColor = theme.darkTile.withValues(alpha: 0.4);

    final bgTop = theme.background?.colors.first ?? const Color(0xFF0A0F0C);
    final isDarkBg =
        ThemeData.estimateBrightnessForColor(bgTop) == Brightness.dark;

    final trackBgColor =
        isDarkBg ? const Color(0x660E0E0E) : const Color(0x1A000000);
    final trackBorderColor =
        isDarkBg ? const Color(0x14FFFFFF) : const Color(0x1F000000);
    final inactiveTextColor =
        isDarkBg ? const Color(0x99C3C8C2) : const Color(0x99313030);

    final options = [3, 5, 8, 12];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PEEK TOKEN FREQUENCY',
          style: TextStyle(
            color: primaryColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Moves required to earn 1 peek token',
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
              ...options.map((level) {
                final isSelected = peekState.peekFrequency == level;
                return _buildOption(
                  context: context,
                  label: '$level',
                  isSelected: isSelected,
                  primaryColor: primaryColor,
                  activeBgColor: activeBgColor,
                  inactiveTextColor: inactiveTextColor,
                  onTap: () {
                    prov.Provider.of<AppModel>(context, listen: false)
                        .haptic
                        .light();
                    notifier.configureFrequency(level);
                  },
                );
              }),
              _buildOption(
                context: context,
                label: (!options.contains(peekState.peekFrequency))
                    ? '${peekState.peekFrequency}'
                    : '+',
                isSelected: !options.contains(peekState.peekFrequency),
                primaryColor: primaryColor,
                activeBgColor: activeBgColor,
                inactiveTextColor: inactiveTextColor,
                onTap: () {
                  prov.Provider.of<AppModel>(context, listen: false)
                      .haptic
                      .light();
                  _showCustomFrequencyDialog(context, notifier, primaryColor);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOption({
    required BuildContext context,
    required String label,
    required bool isSelected,
    required Color primaryColor,
    required Color activeBgColor,
    required Color inactiveTextColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? activeBgColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? primaryColor : inactiveTextColor,
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  void _showCustomFrequencyDialog(
      BuildContext context, PeekingNotifier notifier, Color primaryColor) {
    final controller = TextEditingController();
    String? errorMessage;

    showGeneralDialog<void>(
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
                child: StatefulBuilder(
                  builder: (dialogContext, setState) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Custom Frequency',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE5E2E1),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Enter moves required for a peek token',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFFC3C8C2),
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        CupertinoTextField(
                          controller: controller,
                          keyboardType: TextInputType.number,
                          autofocus: true,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18),
                          cursorColor: primaryColor,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: errorMessage != null
                                  ? Colors.redAccent
                                  : Colors.white.withValues(alpha: 0.1),
                              width: 1,
                            ),
                          ),
                          placeholder: 'Moves',
                          placeholderStyle:
                              const TextStyle(color: Colors.grey, fontSize: 16),
                          onChanged: (_) {
                            if (errorMessage != null) {
                              setState(() {
                                errorMessage = null;
                              });
                            }
                          },
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            errorMessage!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          children: [
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
                                      color:
                                          Colors.white.withValues(alpha: 0.1),
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
                            Expanded(
                              child: CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  final int? val =
                                      int.tryParse(controller.text);
                                  if (val == null || val <= 0) {
                                    setState(() {
                                      errorMessage =
                                          'Please enter a valid number';
                                    });
                                  } else {
                                    notifier.configureFrequency(val);
                                    Navigator.pop(dialogContext);
                                  }
                                },
                                child: Container(
                                  height: 46,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5F5F0),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Text(
                                    'Set',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
