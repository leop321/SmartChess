import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../model/app_model.dart';
import '../model/app_themes.dart';
import 'blind_chess_view.dart';
import 'home_view.dart';
import 'settings_view.dart';
import 'tactics_view.dart';

class MainNavigationContainer extends StatefulWidget {
  const MainNavigationContainer({Key? key}) : super(key: key);

  @override
  _MainNavigationContainerState createState() =>
      _MainNavigationContainerState();
}

class _MainNavigationContainerState extends State<MainNavigationContainer>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;

  // Lazy-instantiated pages so we don't rebuild tabs when switching.
  static const _pages = [
    HomeView(),
    TacticsView(),
    BlindChessView(),
    SettingsView(isTab: true),
  ];

  @override
  Widget build(BuildContext context) {
    return Selector<AppModel, AppTheme>(
      selector: (_, m) => m.theme,
      builder: (context, theme, child) {
        return Scaffold(
          body: Stack(
            children: [
              // Keep all pages alive with IndexedStack so state is preserved.
              IndexedStack(
                index: _currentIndex,
                children: _pages,
              ),

              // Custom glassy bottom nav bar
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _GlassNavBar(
                  currentIndex: _currentIndex,
                  theme: theme,
                  onTap: (index) {
                    if (index != _currentIndex) {
                      final appModel =
                          Provider.of<AppModel>(context, listen: false);
                      appModel.haptic.selection();
                      setState(() => _currentIndex = index);
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────
// Custom Glassy Nav Bar
// ─────────────────────────────────────────────────────

class _GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final AppTheme theme;
  final ValueChanged<int> onTap;

  const _GlassNavBar({
    required this.currentIndex,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final navHeight = 60.0 + (bottomPadding > 0 ? bottomPadding : 16.0);

    final bgColor =
        isAndroid ? const Color(0xDD121212) : const Color(0x60121212);

    Widget bar = Container(
      height: navHeight,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(
            color: theme.lightTile.withValues(alpha: 0.10),
            width: 0.5,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding > 0 ? bottomPadding : 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _NavItem(
              index: 0,
              currentIndex: currentIndex,
              theme: theme,
              icon: Icons.home_rounded,
              activeIcon: Icons.home_rounded,
              label: 'Home',
              onTap: onTap,
            ),
            _NavItem(
              index: 1,
              currentIndex: currentIndex,
              theme: theme,
              icon: Icons.extension_outlined,
              activeIcon: Icons.extension_rounded,
              label: 'Tactics',
              onTap: onTap,
            ),
            _BlindChessNavItem(
              index: 2,
              currentIndex: currentIndex,
              theme: theme,
              onTap: onTap,
            ),
            _NavItem(
              index: 3,
              currentIndex: currentIndex,
              theme: theme,
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings_rounded,
              label: 'Settings',
              onTap: onTap,
            ),
          ],
        ),
      ),
    );

    if (!isAndroid) {
      bar = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: bar,
        ),
      );
    }

    return bar;
  }
}

class _NavItem extends StatelessWidget {
  final int index;
  final int currentIndex;
  final AppTheme theme;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.index,
    required this.currentIndex,
    required this.theme,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == currentIndex;

    return Expanded(
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              width: 40,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isActive
                    ? theme.lightTile.withValues(alpha: 0.12)
                    : Colors.transparent,
              ),
              child: Center(
                child: Icon(
                  isActive ? activeIcon : icon,
                  color: isActive
                      ? theme.lightTile
                      : const Color(0xFFE5E2E1).withValues(alpha: 0.35),
                  size: 22,
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                color: isActive
                    ? theme.lightTile
                    : const Color(0xFFE5E2E1).withValues(alpha: 0.35),
                fontFamily: 'Inter',
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

// Blindchess nav item with custom painter pawn+blindfold icon
class _BlindChessNavItem extends StatelessWidget {
  final int index;
  final int currentIndex;
  final AppTheme theme;
  final ValueChanged<int> onTap;

  const _BlindChessNavItem({
    required this.index,
    required this.currentIndex,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == currentIndex;
    return Expanded(
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              width: 40,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isActive
                    ? theme.lightTile.withValues(alpha: 0.12)
                    : Colors.transparent,
              ),
              child: Center(
                child: CustomPaint(
                  size: const Size(20, 20),
                  painter: _BlindPawnNavPainter(
                    color: isActive
                        ? theme.lightTile
                        : const Color(0xFFE5E2E1).withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                color: isActive
                    ? theme.lightTile
                    : const Color(0xFFE5E2E1).withValues(alpha: 0.35),
                fontFamily: 'Inter',
              ),
              child: const Text('Blind'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact pawn silhouette with a blindfold band for the nav bar icon.
class _BlindPawnNavPainter extends CustomPainter {
  final Color color;
  const _BlindPawnNavPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Head
    canvas.drawCircle(Offset(w * 0.5, h * 0.18), w * 0.18, paint);

    // Neck
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(w * 0.5, h * 0.40),
            width: w * 0.17,
            height: h * 0.2),
        Radius.circular(w * 0.04),
      ),
      paint,
    );

    // Body (trapezoid)
    final bodyPath = Path()
      ..moveTo(w * 0.16, h * 0.88)
      ..lineTo(w * 0.84, h * 0.88)
      ..lineTo(w * 0.7, h * 0.50)
      ..lineTo(w * 0.3, h * 0.50)
      ..close();
    canvas.drawPath(bodyPath, paint);

    // Base
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.04, h * 0.87, w * 0.92, h * 0.11),
        Radius.circular(w * 0.05),
      ),
      paint,
    );

    // Blindfold band (draw as a dark cut-out over the head)
    final cutPaint = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(w * 0.5, h * 0.175),
            width: w * 0.44,
            height: h * 0.09),
        Radius.circular(w * 0.03),
      ),
      cutPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BlindPawnNavPainter old) => old.color != color;
}
