import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/shared_functions.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import 'components/shared/glass_panel.dart';
import 'game_setup_view.dart';

class HomeView extends StatelessWidget {
  const HomeView({Key? key}) : super(key: key);

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
                // 1. Dot Grid
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: DotGridPainter(
                          color: theme.lightTile.withValues(alpha: 0.05)),
                    ),
                  ),
                ),

                // 2. Glow blob top-right
                Positioned(
                  top: 60,
                  right: -60,
                  child: RepaintBoundary(
                    child: Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: theme.lightTile.withValues(alpha: 0.06),
                            blurRadius: 120,
                            spreadRadius: 30,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. Content
                SafeArea(
                  bottom: false,
                  child: Consumer<AppModel>(
                    builder: (context, appModel, _) {
                      return ListView(
                        padding: const EdgeInsets.only(
                            left: 20, right: 20, bottom: 120),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          const SizedBox(height: 16),
                          // Profile Header
                          _ProfileHeaderWidget(appModel: appModel),
                          const SizedBox(height: 24),
                          // Rating Card
                          _RatingWidget(appModel: appModel),
                          const SizedBox(height: 16),
                          // Beaten Bots Card
                          _BeatenBotsWidget(appModel: appModel),
                          const SizedBox(height: 24),
                          // Play Button
                          _PlayButtonWidget(appModel: appModel),
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
// Profile Header Widget
// ─────────────────────────────────────────────────────

class _ProfileHeaderWidget extends StatelessWidget {
  final AppModel appModel;
  const _ProfileHeaderWidget({required this.appModel});

  @override
  Widget build(BuildContext context) {
    final theme = appModel.theme;
    return Row(
      children: [
        // Avatar button
        GestureDetector(
          onTap: () {
            appModel.haptic.light();
            _showProfileDialog(context, appModel);
          },
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.lightTile.withValues(alpha: 0.12),
              border: Border.all(
                color: theme.lightTile.withValues(alpha: 0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.lightTile.withValues(alpha: 0.15),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipOval(
              child: _PieceAvatar(
                avatar: appModel.userAvatar,
                pieceTheme: appModel.pieceTheme,
                size: 56,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appModel.userName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE5E2E1),
                  letterSpacing: -0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                _rankTitle(appModel.userRating),
                style: TextStyle(
                  fontSize: 13,
                  color: theme.lightTile.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        // Edit hint icon
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            appModel.haptic.light();
            _showProfileDialog(context, appModel);
          },
          child: Icon(
            Icons.edit_outlined,
            color: theme.lightTile.withValues(alpha: 0.6),
            size: 20,
          ),
        ),
      ],
    );
  }

  String _rankTitle(int rating) {
    if (rating < 600) return 'Beginner';
    if (rating < 1000) return 'Casual';
    if (rating < 1400) return 'Intermediate';
    if (rating < 1800) return 'Advanced';
    return 'Master';
  }
}

// ─────────────────────────────────────────────────────
// Rating Widget
// ─────────────────────────────────────────────────────

class _RatingWidget extends StatelessWidget {
  final AppModel appModel;
  const _RatingWidget({required this.appModel});

  @override
  Widget build(BuildContext context) {
    final theme = appModel.theme;
    final rating = appModel.userRating;
    final (nextMilestone, prevMilestone) = _milestones(rating);
    final progress = (rating - prevMilestone) / (nextMilestone - prevMilestone);

    final now = DateTime.now();
    final todayStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final isToday = appModel.lastGameDate == todayStr;
    final change =
        isToday ? appModel.todayRatingChange : appModel.lastGameRatingChange;

    return GlassPanel(
      borderRadius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RATING',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: theme.lightTile.withValues(alpha: 0.6),
                  letterSpacing: 2,
                ),
              ),
              Icon(Icons.bar_chart_rounded,
                  color: theme.lightTile.withValues(alpha: 0.5), size: 18),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '$rating',
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFE5E2E1),
                  letterSpacing: -1,
                  height: 1,
                ),
              ),
              const SizedBox(width: 10),
              if (change != 0) _buildChangeIndicator(change, isToday),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _rankTitle(rating),
            style: TextStyle(
              fontSize: 14,
              color: theme.lightTile,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          // Progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$prevMilestone',
                    style: TextStyle(
                        fontSize: 11,
                        color: const Color(0xFFE5E2E1).withValues(alpha: 0.4)),
                  ),
                  Text(
                    'Next Level: $nextMilestone',
                    style: TextStyle(
                        fontSize: 11,
                        color: const Color(0xFFE5E2E1).withValues(alpha: 0.4)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: theme.lightTile.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(theme.lightTile),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _rankTitle(int rating) {
    if (rating < 600) return 'Beginner';
    if (rating < 1000) return 'Casual';
    if (rating < 1400) return 'Intermediate';
    if (rating < 1800) return 'Advanced';
    return 'Master';
  }

  (int, int) _milestones(int rating) {
    const milestones = [0, 600, 1000, 1400, 1800, 3200];
    for (int i = 0; i < milestones.length - 1; i++) {
      if (rating < milestones[i + 1]) {
        return (milestones[i + 1], milestones[i]);
      }
    }
    return (3200, 1800);
  }

  Widget _buildChangeIndicator(int change, bool isToday) {
    final isPositive = change > 0;
    final color =
        isPositive ? const Color(0xFF4CAF50) : const Color(0xFFFF5252);
    final sign = isPositive ? '+' : '';
    final label = isToday ? 'today' : 'last game';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        '$sign$change ($label)',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
          shadows: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// Beaten Bots Widget
// ─────────────────────────────────────────────────────

class _BeatenBotsWidget extends StatelessWidget {
  final AppModel appModel;
  const _BeatenBotsWidget({required this.appModel});

  static const _bots = [
    (1, 'Beginner', 400),
    (2, 'Casual', 800),
    (3, 'Intermediate', 1200),
    (4, 'Advanced', 1600),
    (5, 'Master', 2000),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = appModel.theme;
    final beaten = appModel.beatenBots;

    return GlassPanel(
      borderRadius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'BOT CHALLENGES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: theme.lightTile.withValues(alpha: 0.6),
                  letterSpacing: 2,
                ),
              ),
              Text(
                '${beaten.length}/${_bots.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: theme.lightTile.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._bots.map((bot) {
            final (difficulty, name, elo) = bot;
            final isBeaten = beaten.contains(difficulty);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  // Status icon
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isBeaten
                          ? theme.lightTile.withValues(alpha: 0.15)
                          : const Color(0xFF1E1E1E).withValues(alpha: 0.5),
                      border: Border.all(
                        color: isBeaten
                            ? theme.lightTile.withValues(alpha: 0.5)
                            : const Color(0xFFFFFFFF).withValues(alpha: 0.08),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: isBeaten
                          ? Icon(Icons.check_rounded,
                              color: theme.lightTile, size: 16)
                          : Icon(Icons.lock_outline_rounded,
                              color: const Color(0xFFE5E2E1)
                                  .withValues(alpha: 0.3),
                              size: 14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isBeaten
                                ? const Color(0xFFE5E2E1)
                                : const Color(0xFFE5E2E1)
                                    .withValues(alpha: 0.45),
                          ),
                        ),
                        Text(
                          '$elo ELO',
                          style: TextStyle(
                            fontSize: 11,
                            color: isBeaten
                                ? theme.lightTile.withValues(alpha: 0.6)
                                : const Color(0xFFE5E2E1)
                                    .withValues(alpha: 0.25),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isBeaten)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.lightTile.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Defeated',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: theme.lightTile,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// Play Button Widget
// ─────────────────────────────────────────────────────

class _PlayButtonWidget extends StatelessWidget {
  final AppModel appModel;
  const _PlayButtonWidget({required this.appModel});

  @override
  Widget build(BuildContext context) {
    final theme = appModel.theme;
    final primaryBg = theme.moveHint.withValues(alpha: 1.0);
    final isDark =
        ThemeData.estimateBrightnessForColor(primaryBg) == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF241A00);

    return Selector<AppModel, bool>(
      selector: (_, m) => m.imagesReady,
      builder: (context, ready, _) {
        return Container(
          width: double.infinity,
          height: 62,
          decoration: BoxDecoration(
            color: primaryBg.withValues(alpha: ready ? 1.0 : 0.55),
            borderRadius: BorderRadius.circular(32),
            boxShadow: ready
                ? [
                    BoxShadow(
                      color: primaryBg.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: ready
                ? () {
                    appModel.haptic.light();
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (context) => const GameSetupView(),
                      ),
                    );
                  }
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (ready) ...[
                  // Pawn icon from current piece theme
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: Image.asset(
                      'assets/images/pieces/${formatPieceTheme(appModel.pieceTheme)}/pawn_white.png',
                      fit: BoxFit.contain,
                      color: textColor,
                      colorBlendMode: BlendMode.srcIn,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.sports_esports_outlined,
                        color: textColor,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  ready ? 'PLAY' : '',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.5,
                  ),
                ),
                if (!ready)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: textColor.withValues(alpha: 0.7),
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
// Piece Avatar Widget
// ─────────────────────────────────────────────────────

class _PieceAvatar extends StatelessWidget {
  final String avatar; // e.g. "king_white", "pawn_black"
  final String pieceTheme;
  final double size;

  const _PieceAvatar({
    required this.avatar,
    required this.pieceTheme,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final path =
        'assets/images/pieces/${formatPieceTheme(pieceTheme)}/$avatar.png';
    return Padding(
      padding: EdgeInsets.all(size * 0.12),
      child: Image.asset(
        path,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(
          Icons.person,
          size: size * 0.6,
          color: const Color(0xFFC3C8C2),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// Profile Dialog
// ─────────────────────────────────────────────────────

void _showProfileDialog(BuildContext context, AppModel appModel) {
  showGeneralDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.65),
    barrierDismissible: true,
    barrierLabel: '',
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (dialogContext, anim1, anim2) {
      return _ProfileDialogContent(
        appModel: appModel,
        animation: anim1,
      );
    },
    transitionBuilder: (context, anim1, anim2, child) {
      return FadeTransition(
        opacity: anim1.drive(CurveTween(curve: Curves.easeOut)),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(anim1),
          child: child,
        ),
      );
    },
  );
}

class _ProfileDialogContent extends StatefulWidget {
  final AppModel appModel;
  final Animation<double> animation;

  const _ProfileDialogContent({
    required this.appModel,
    required this.animation,
  });

  @override
  State<_ProfileDialogContent> createState() => _ProfileDialogContentState();
}

class _ProfileDialogContentState extends State<_ProfileDialogContent> {
  late TextEditingController _nameController;
  late String _selectedAvatar;
  bool _confirmReset = false;

  static const _pieces = ['king', 'queen', 'rook', 'bishop', 'knight', 'pawn'];
  static const _colors = ['white', 'black'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.appModel.userName);
    _selectedAvatar = widget.appModel.userAvatar;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appModel = widget.appModel;
    final theme = appModel.theme;
    final pieceTheme = appModel.pieceTheme;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: GlassPanel(
          borderRadius: 28,
          padding: const EdgeInsets.all(24),
          color: const Color(0x85181818),
          animation: widget.animation,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                const Text(
                  'Edit Profile',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE5E2E1),
                  ),
                ),
                const SizedBox(height: 20),

                // Name field
                Text(
                  'NAME',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: theme.lightTile.withValues(alpha: 0.6),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1C).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.lightTile.withValues(alpha: 0.2),
                    ),
                  ),
                  child: CupertinoTextField(
                    controller: _nameController,
                    style: const TextStyle(
                      color: Color(0xFFE5E2E1),
                      fontSize: 16,
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: null,
                    maxLength: 20,
                    placeholder: 'Your Name',
                    placeholderStyle: TextStyle(
                        color: const Color(0xFFE5E2E1).withValues(alpha: 0.3)),
                    cursorColor: theme.lightTile,
                  ),
                ),
                const SizedBox(height: 20),

                // Avatar picker
                Text(
                  'AVATAR',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: theme.lightTile.withValues(alpha: 0.6),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                _buildAvatarGrid(theme, pieceTheme),

                const SizedBox(height: 20),

                // Reset stats
                if (_confirmReset)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Reset rating & bots?',
                            style: TextStyle(
                                fontSize: 13, color: Color(0xFFE5E2E1)),
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () =>
                              setState(() => _confirmReset = false),
                          child: const Text('No',
                              style: TextStyle(
                                  color: Color(0xFFA0A8A4), fontSize: 13)),
                        ),
                        const SizedBox(width: 8),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () async {
                            await appModel.resetStats();
                            setState(() => _confirmReset = false);
                          },
                          child: const Text('Yes',
                              style: TextStyle(
                                  color: Colors.redAccent, fontSize: 13)),
                        ),
                      ],
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => setState(() => _confirmReset = true),
                    child: Row(
                      children: [
                        Icon(Icons.restart_alt_rounded,
                            color:
                                const Color(0xFFE5E2E1).withValues(alpha: 0.35),
                            size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Reset Statistics',
                          style: TextStyle(
                            fontSize: 13,
                            color:
                                const Color(0xFFE5E2E1).withValues(alpha: 0.35),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 20),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: _dialogButton(
                        label: 'Cancel',
                        isPrimary: false,
                        theme: theme,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _dialogButton(
                        label: 'Save',
                        isPrimary: true,
                        theme: theme,
                        onPressed: () async {
                          final name = _nameController.text.trim();
                          if (name.isNotEmpty) {
                            await appModel.setUserName(name);
                          }
                          await appModel.setUserAvatar(_selectedAvatar);
                          if (context.mounted) Navigator.pop(context);
                        },
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
  }

  Widget _buildAvatarGrid(AppTheme theme, String pieceTheme) {
    return SizedBox(
      height: 130,
      child: GridView.count(
        crossAxisCount: 6,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (final color in _colors)
            for (final piece in _pieces)
              _buildAvatarCell(
                '${piece}_$color',
                pieceTheme,
                theme,
              ),
        ],
      ),
    );
  }

  Widget _buildAvatarCell(String avatar, String pieceTheme, AppTheme theme) {
    final isSelected = _selectedAvatar == avatar;
    return GestureDetector(
      onTap: () {
        widget.appModel.haptic.selection();
        setState(() => _selectedAvatar = avatar);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected
              ? theme.lightTile.withValues(alpha: 0.18)
              : const Color(0xFF1C1C1C).withValues(alpha: 0.5),
          border: Border.all(
            color: isSelected
                ? theme.lightTile
                : const Color(0xFFFFFFFF).withValues(alpha: 0.08),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.lightTile.withValues(alpha: 0.25),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: _PieceAvatar(avatar: avatar, pieceTheme: pieceTheme, size: 40),
      ),
    );
  }

  Widget _dialogButton({
    required String label,
    required bool isPrimary,
    required AppTheme theme,
    required VoidCallback onPressed,
  }) {
    final bg =
        isPrimary ? theme.moveHint : Colors.white.withValues(alpha: 0.06);
    final isDark =
        ThemeData.estimateBrightnessForColor(isPrimary ? bg : Colors.black) ==
            Brightness.dark;
    final textColor = isPrimary
        ? (isDark ? Colors.white : const Color(0xFF241A00))
        : const Color(0xFFC3C8C2);

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: isPrimary
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
