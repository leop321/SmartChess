import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../model/app_model.dart';
import '../model/app_themes.dart';
import 'components/shared/glass_panel.dart';

class BlindChessView extends StatelessWidget {
  const BlindChessView({Key? key}) : super(key: key);

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
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: DotGridPainter(
                          color: theme.lightTile.withValues(alpha: 0.05)),
                    ),
                  ),
                ),
                Positioned(
                  top: 80,
                  left: -60,
                  child: RepaintBoundary(
                    child: Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: theme.moveHint.withValues(alpha: 0.06),
                            blurRadius: 120,
                            spreadRadius: 30,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        child: Row(
                          children: [
                            const Text(
                              'Blindschach',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFE5E2E1),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: GlassPanel(
                              borderRadius: 24,
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CustomPaint(
                                    size: const Size(56, 56),
                                    painter: _BlindPawnPainter(
                                        color: theme.lightTile),
                                  ),
                                  const SizedBox(height: 20),
                                  const Text(
                                    'Blind Chess',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFE5E2E1),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Play chess without seeing the board.\nComing soon.',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: Color(0xFFA0A8A4),
                                      height: 1.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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

/// A simple pawn silhouette with a blindfold band across the middle.
class _BlindPawnPainter extends CustomPainter {
  final Color color;
  const _BlindPawnPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Body (simplified pawn shape)
    // Head circle
    canvas.drawCircle(Offset(w * 0.5, h * 0.18), w * 0.18, paint);
    // Neck
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(w * 0.5, h * 0.42),
            width: w * 0.18,
            height: h * 0.2),
        Radius.circular(w * 0.04),
      ),
      paint,
    );
    // Body (wider trapezoid-like)
    final bodyPath = Path()
      ..moveTo(w * 0.18, h * 0.88)
      ..lineTo(w * 0.82, h * 0.88)
      ..lineTo(w * 0.7, h * 0.52)
      ..lineTo(w * 0.3, h * 0.52)
      ..close();
    canvas.drawPath(bodyPath, paint);
    // Base
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.06, h * 0.87, w * 0.88, h * 0.1),
        Radius.circular(w * 0.05),
      ),
      paint,
    );

    // Blindfold band across head
    final blindfoldPaint = Paint()
      ..color = const Color(0xFF0A0A0A).withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.18),
          width: w * 0.46,
          height: h * 0.10,
        ),
        Radius.circular(w * 0.04),
      ),
      blindfoldPaint,
    );
    // Small knot on the right side of the blindfold
    canvas.drawCircle(Offset(w * 0.72, h * 0.18), w * 0.04, blindfoldPaint);
  }

  @override
  bool shouldRepaint(covariant _BlindPawnPainter old) => old.color != color;
}
