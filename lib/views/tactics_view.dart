import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../model/app_model.dart';
import '../model/app_themes.dart';
import 'components/shared/glass_panel.dart';

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

// ─────────────────────────────────────────────────────
// Main TacticsView (Clean UI Shell)
// ─────────────────────────────────────────────────────

class TacticsView extends StatelessWidget {
  const TacticsView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Selector<AppModel, AppTheme>(
      selector: (_, m) => m.theme,
      builder: (context, theme, _) {
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

                // 2. Ambient Glow Blob Top-Right
                Positioned(
                  top: 80,
                  right: -50,
                  child: RepaintBoundary(
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: theme.lightTile.withValues(alpha: 0.06),
                            blurRadius: 110,
                            spreadRadius: 25,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. Main Content
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),

                        // Section Title
                        Text(
                          'TAKTIK',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: theme.lightTile.withValues(alpha: 0.6),
                            letterSpacing: 3.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Puzzles & Training',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFE5E2E1),
                            letterSpacing: -0.5,
                          ),
                        ),

                        const Spacer(),

                        // Center Placeholder Card
                        Center(
                          child: GlassPanel(
                            borderRadius: 24,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 36,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Icon badge
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: theme.lightTile.withValues(alpha: 0.12),
                                    border: Border.all(
                                      color: theme.lightTile.withValues(alpha: 0.25),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.psychology_rounded,
                                      size: 38,
                                      color: theme.lightTile,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Status Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.moveHint.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: theme.moveHint.withValues(alpha: 0.35),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    'DEMNÄCHST VERFÜGBAR',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: theme.moveHint,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Title
                                const Text(
                                  'Taktikaufgaben in Überarbeitung',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFE5E2E1),
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // Subtitle
                                Text(
                                  'Ein neues, stabiles Taktik-Modul wird vorbereitet und steht in Kürze bereit.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.4,
                                    color: const Color(0xFFE5E2E1).withValues(alpha: 0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const Spacer(flex: 2),
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
