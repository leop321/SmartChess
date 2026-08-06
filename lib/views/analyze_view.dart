import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/chess_api_service.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/game_analysis_models.dart';
import 'components/analyze_view/analyze_game_bottom_sheet.dart';
import 'components/analyze_view/game_analysis_page.dart';
import 'components/analyze_view/game_history_tile.dart';
import 'components/analyze_view/player_insights_page.dart';

/// Main Analysis tab — the hub for all analysis features.
/// Replaces the former BlindChessView as the 3rd nav tab.
///
/// Three UI states:
///   A — No accounts linked → infotile + disabled buttons
///   B — Accounts linked, not yet loaded → buttons + empty history prompt
///   C — Accounts linked + games loaded → full game history
class AnalyzeView extends StatefulWidget {
  const AnalyzeView({Key? key}) : super(key: key);

  @override
  State<AnalyzeView> createState() => _AnalyzeViewState();
}

class _AnalyzeViewState extends State<AnalyzeView>
    with AutomaticKeepAliveClientMixin {
  final _api = ChessApiService();
  List<GameEntry> _recentGames = [];
  List<GameEntry> _filteredGames = [];
  bool _isLoading = false;
  bool _hasFetched = false;

  // ── Filter state ──
  String? _filterAccount; // null = all
  String? _filterResult; // null | 'win' | 'loss' | 'draw'
  String? _filterMode; // null | 'bullet' | 'blitz' | 'rapid' | 'classical'
  DateTime? _filterFrom;
  DateTime? _filterTo;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appModel = context.read<AppModel>();
      if (appModel.hasLinkedAccounts && !_hasFetched) {
        _loadRecentGames(appModel);
      }
    });
  }

  Future<void> _loadRecentGames(AppModel appModel) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _hasFetched = true;
    });

    final games = <GameEntry>[];

    if (appModel.lichessUsername.isNotEmpty) {
      try {
        final lichessGames = await _api.fetchLichessGames(
          appModel.lichessUsername,
          maxGames: 15,
        );
        games.addAll(lichessGames);
      } catch (_) {}
    }

    if (appModel.chessComUsername.isNotEmpty) {
      try {
        final chessComGames = await _api.fetchChessComGames(
          appModel.chessComUsername,
          maxGames: 15,
        );
        games.addAll(chessComGames);
      } catch (_) {}
    }

    games.sort((a, b) => b.date.compareTo(a.date));

    if (mounted) {
      setState(() {
        _recentGames = games;
        _filteredGames = games;
        _isLoading = false;
      });
    }
  }

  void _applyFilters(AppModel appModel) {
    setState(() {
      _filteredGames = _recentGames.where((g) {
        // Account filter
        if (_filterAccount != null) {
          if (_filterAccount == appModel.lichessUsername &&
              g.platform != GamePlatform.lichess) return false;
          if (_filterAccount == appModel.chessComUsername &&
              g.platform != GamePlatform.chessCom) return false;
        }

        // Result filter (we evaluate from the linked username's perspective)
        if (_filterResult != null) {
          final myUser = g.platform == GamePlatform.lichess
              ? appModel.lichessUsername.toLowerCase()
              : appModel.chessComUsername.toLowerCase();
          final iPlayWhite = g.white.toLowerCase() == myUser;
          final myColor = iPlayWhite ? 'white' : 'black';
          final won = g.winner == myColor;
          final drew = g.winner == 'draw' || g.winner.isEmpty;
          if (_filterResult == 'win' && !won) return false;
          if (_filterResult == 'loss' && (won || drew)) return false;
          if (_filterResult == 'draw' && !drew) return false;
        }

        // Mode filter
        if (_filterMode != null && g.speed != _filterMode) return false;

        // Date range
        if (_filterFrom != null && g.date.isNotEmpty) {
          try {
            final d = DateTime.parse(g.date);
            if (d.isBefore(_filterFrom!)) return false;
          } catch (_) {}
        }
        if (_filterTo != null && g.date.isNotEmpty) {
          try {
            final d = DateTime.parse(g.date);
            if (d.isAfter(_filterTo!.add(const Duration(days: 1)))) {
              return false;
            }
          } catch (_) {}
        }
        return true;
      }).toList();
    });
  }

  bool get _hasActiveFilters =>
      _filterAccount != null ||
      _filterResult != null ||
      _filterMode != null ||
      _filterFrom != null ||
      _filterTo != null;

  // ─── Filter Bottom Sheet ────────────────────────────────────────────────────

  void _showFilterSheet(AppModel appModel, AppTheme theme) {
    final accent = theme.lightTile;
    String? tmpAccount = _filterAccount;
    String? tmpResult = _filterResult;
    String? tmpMode = _filterMode;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          Widget chipRow({
            required String label,
            required List<(String, String)> options, // (value, display)
            required String? selected,
            required void Function(String?) onSelect,
          }) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(label,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        fontFamily: 'Inter',
                      )),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FilterChip(
                      label: 'All',
                      selected: selected == null,
                      accent: accent,
                      onTap: () => setModal(() => onSelect(null)),
                    ),
                    ...options.map((o) => _FilterChip(
                          label: o.$2,
                          selected: selected == o.$1,
                          accent: accent,
                          onTap: () => setModal(() => onSelect(o.$1)),
                        )),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            );
          }

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF111928),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08), width: 0.5),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text('Filter Games',
                            style: TextStyle(
                              color: accent,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Inter',
                            )),
                        const Spacer(),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            setModal(() {
                              tmpAccount = null;
                              tmpResult = null;
                              tmpMode = null;
                            });
                          },
                          child: Text('Reset',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 13,
                                fontFamily: 'Inter',
                              )),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Account filter
                    if (appModel.lichessUsername.isNotEmpty ||
                        appModel.chessComUsername.isNotEmpty)
                      chipRow(
                        label: 'ACCOUNT',
                        options: [
                          if (appModel.lichessUsername.isNotEmpty)
                            (
                              appModel.lichessUsername,
                              '♟ ${appModel.lichessUsername}'
                            ),
                          if (appModel.chessComUsername.isNotEmpty)
                            (
                              appModel.chessComUsername,
                              '♞ ${appModel.chessComUsername}'
                            ),
                        ],
                        selected: tmpAccount,
                        onSelect: (v) => tmpAccount = v,
                      ),

                    // Result filter
                    chipRow(
                      label: 'RESULT',
                      options: const [
                        ('win', '✓ Win'),
                        ('loss', '✗ Loss'),
                        ('draw', '½ Draw'),
                      ],
                      selected: tmpResult,
                      onSelect: (v) => tmpResult = v,
                    ),

                    // Mode filter
                    chipRow(
                      label: 'MODE',
                      options: const [
                        ('bullet', '⚡ Bullet'),
                        ('blitz', '🔥 Blitz'),
                        ('rapid', '⏱ Rapid'),
                        ('classical', '♜ Classical'),
                      ],
                      selected: tmpMode,
                      onSelect: (v) => tmpMode = v,
                    ),

                    // Apply button
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() {
                            _filterAccount = tmpAccount;
                            _filterResult = tmpResult;
                            _filterMode = tmpMode;
                          });
                          _applyFilters(appModel);
                        },
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              accent.withValues(alpha: 0.85),
                              accent.withValues(alpha: 0.6),
                            ]),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'Apply Filters',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Selector<AppModel, (AppTheme, bool, String, String)>(
      selector: (_, m) => (
        m.theme,
        m.hasLinkedAccounts,
        m.lichessUsername,
        m.chessComUsername,
      ),
      builder: (context, data, _) {
        final theme = data.$1;
        final hasAccounts = data.$2;
        final lichessUser = data.$3;
        final chessComUser = data.$4;
        final accent = theme.lightTile;
        final appModel = context.read<AppModel>();

        return Scaffold(
          backgroundColor: const Color(0xFF0E1420),
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── Header ──────────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _buildHeader(
                    theme: theme,
                    accent: accent,
                    hasAccounts: hasAccounts,
                    lichessUser: lichessUser,
                    chessComUser: chessComUser,
                    appModel: appModel,
                  ),
                ),

                // ── No account infotile ──────────────────────────────────────
                if (!hasAccounts)
                  SliverToBoxAdapter(
                    child: _buildNoAccountTile(accent, appModel),
                  ),

                // ── Account chips (when accounts linked) ─────────────────────
                if (hasAccounts)
                  SliverToBoxAdapter(
                    child: _buildAccountChips(
                        lichessUser, chessComUser, accent, context),
                  ),

                // ── Action buttons ────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _buildActionButtons(
                      theme: theme,
                      accent: accent,
                      hasAccounts: hasAccounts,
                      lichessUser: lichessUser,
                      chessComUser: chessComUser),
                ),

                // ── Games header ──────────────────────────────────────────────
                if (hasAccounts)
                  SliverToBoxAdapter(
                    child: _buildGamesHeader(accent, theme, appModel),
                  ),

                // ── Loading ───────────────────────────────────────────────────
                if (_isLoading)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: CircularProgressIndicator(color: accent),
                      ),
                    ),
                  ),

                // ── Empty state ───────────────────────────────────────────────
                if (!_isLoading && hasAccounts && _recentGames.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: Column(
                        children: [
                          Text(
                            '♟',
                            style: TextStyle(
                                color: accent.withValues(alpha: 0.3),
                                fontSize: 48),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No games loaded yet.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 15,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── No results after filter ────────────────────────────────────
                if (!_isLoading &&
                    _recentGames.isNotEmpty &&
                    _filteredGames.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Column(
                        children: [
                          Icon(Icons.filter_list_off_rounded,
                              color: accent.withValues(alpha: 0.3), size: 40),
                          const SizedBox(height: 12),
                          Text(
                            'No games match these filters.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 15,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Game list ─────────────────────────────────────────────────
                if (!_isLoading && _filteredGames.isNotEmpty)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final game = _filteredGames[i];
                        return GameHistoryTile(
                          game: game,
                          theme: theme,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GameAnalysisPage(game: game),
                            ),
                          ),
                        );
                      },
                      childCount: _filteredGames.length,
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Header ──────────────────────────────────────────────────────────────

  Widget _buildHeader({
    required AppTheme theme,
    required Color accent,
    required bool hasAccounts,
    required String lichessUser,
    required String chessComUser,
    required AppModel appModel,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Analysis',
                style: TextStyle(
                  color: Color(0xFFE5E2E1),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                ),
              ),
              Text(
                hasAccounts
                    ? 'Your game history'
                    : 'Connect an account to get started',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 13,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
          const Spacer(),
          // Refresh button
          if (hasAccounts)
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                setState(() {
                  _recentGames = [];
                  _filteredGames = [];
                  _hasFetched = false;
                });
                _loadRecentGames(appModel);
              },
              child: Icon(
                Icons.refresh_rounded,
                color: accent,
                size: 24,
              ),
            ),
        ],
      ),
    );
  }

  // ─── No Account Tile ──────────────────────────────────────────────────────

  Widget _buildNoAccountTile(Color accent, AppModel appModel) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.12),
            Colors.white.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accent.withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link_off_rounded, color: accent, size: 22),
              const SizedBox(width: 10),
              Text(
                'No account connected',
                style: TextStyle(
                  color: accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Connect your Lichess or Chess.com account in Settings to see your game history and analyse your play.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
              height: 1.5,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 14),
          CupertinoButton(
            onPressed: () {
              // Navigate directly to Settings tab (index 3)
              appModel.setNavIndex(3);
            },
            padding: EdgeInsets.zero,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: accent.withValues(alpha: 0.4), width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.settings_rounded, color: accent, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Open Settings',
                    style: TextStyle(
                      color: accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Account Chips ────────────────────────────────────────────────────────

  Widget _buildAccountChips(
    String lichessUser,
    String chessComUser,
    Color accent,
    BuildContext context,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          if (lichessUser.isNotEmpty)
            _AccountChip(icon: '♟', label: lichessUser, accent: accent),
          if (lichessUser.isNotEmpty && chessComUser.isNotEmpty)
            const SizedBox(width: 8),
          if (chessComUser.isNotEmpty)
            _AccountChip(
                icon: '♞',
                label: chessComUser,
                accent: const Color(0xFF6AAF6A)),
        ],
      ),
    );
  }

  // ─── Action Buttons ───────────────────────────────────────────────────────

  Widget _buildActionButtons({
    required AppTheme theme,
    required Color accent,
    required bool hasAccounts,
    required String lichessUser,
    required String chessComUser,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          // ── Player Insights ──────────────────────────────────────────
          Expanded(
            child: _ActionButton(
              icon: Icons.person_search_rounded,
              label: 'Player\nInsights',
              accent: accent,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlayerInsightsPage(
                      theme: theme,
                      initialUsername: lichessUser.isNotEmpty
                          ? lichessUser
                          : chessComUser.isNotEmpty
                              ? chessComUser
                              : null,
                      initialPlatform:
                          lichessUser.isNotEmpty ? 'Lichess' : 'Chess.com',
                      linkedLichessUser:
                          lichessUser.isNotEmpty ? lichessUser : null,
                      linkedChessComUser:
                          chessComUser.isNotEmpty ? chessComUser : null,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          // ── Analyze Game ─────────────────────────────────────────────
          Expanded(
            child: _ActionButton(
              icon: Icons.analytics_outlined,
              label: 'Analyse\nGame',
              accent: accent,
              onTap: () => AnalyzeGameBottomSheet.show(context, theme),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Games Header ─────────────────────────────────────────────────────────

  Widget _buildGamesHeader(Color accent, AppTheme theme, AppModel appModel) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
      child: Row(
        children: [
          Text(
            'RECENT GAMES',
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              fontFamily: 'Inter',
            ),
          ),
          const Spacer(),
          if (_recentGames.isNotEmpty)
            Text(
              _hasActiveFilters
                  ? '${_filteredGames.length}/${_recentGames.length}'
                  : '${_recentGames.length} games',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 11,
                fontFamily: 'Inter',
              ),
            ),
          const SizedBox(width: 8),
          // Filter button
          if (_recentGames.isNotEmpty)
            GestureDetector(
              onTap: () => _showFilterSheet(appModel, theme),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _hasActiveFilters
                      ? accent.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _hasActiveFilters
                        ? accent.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.filter_list_rounded,
                      color: _hasActiveFilters
                          ? accent
                          : Colors.white.withValues(alpha: 0.4),
                      size: 14,
                    ),
                    if (_hasActiveFilters) ...[
                      const SizedBox(width: 4),
                      Text(
                        'Filtered',
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Filter Chip ──────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? accent : Colors.white70,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }
}

// ─── Action Button ────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.18),
              accent.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: accent.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: accent, size: 24),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.3,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Account Chip ─────────────────────────────────────────────────────────────

class _AccountChip extends StatelessWidget {
  final String icon;
  final String label;
  final Color accent;

  const _AccountChip({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: TextStyle(color: accent, fontSize: 13)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}
