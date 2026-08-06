import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../logic/chess_api_service.dart';
import '../../../logic/player_style_analyzer.dart';
import '../../../model/app_themes.dart';
import '../../../model/game_analysis_models.dart';
import '../analyze_view/game_analysis_page.dart';
import '../analyze_view/game_history_tile.dart';

/// Full-page player insights view — navigated to via Navigator.push.
/// Adapted from MoveLab's _HomePageState (lines 3241–4079).
/// Shows player profile, style radar, recent games; allows searching any username.
class PlayerInsightsPage extends StatefulWidget {
  /// Pre-filled username (from linked account in settings).
  final String? initialUsername;

  /// Pre-selected platform.
  final String? initialPlatform;

  /// App theme for accent colors.
  final AppTheme theme;

  /// Linked accounts to show as quick-search suggestions.
  final String? linkedLichessUser;
  final String? linkedChessComUser;

  const PlayerInsightsPage({
    Key? key,
    this.initialUsername,
    this.initialPlatform,
    this.linkedLichessUser,
    this.linkedChessComUser,
    required this.theme,
  }) : super(key: key);

  @override
  State<PlayerInsightsPage> createState() => _PlayerInsightsPageState();
}

class _PlayerInsightsPageState extends State<PlayerInsightsPage> {
  final _api = ChessApiService();
  late final TextEditingController _searchCtrl;
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;

  String _platform = 'Lichess';
  String _tempo = 'all';

  bool _isLoading = false;
  String _errorMessage = '';
  PlayerProfile? _profile;
  PlayerStyleProfile? _styleProfile;
  List<GameEntry> _games = [];
  List<String> _liveSuggestions = [];
  int _loadedGamesCount = 30;

  @override
  void initState() {
    super.initState();
    _platform = widget.initialPlatform ?? 'Lichess';
    _searchCtrl = TextEditingController(text: widget.initialUsername ?? '');
    if (widget.initialUsername?.isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchStats());
    }
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus) setState(() => _liveSuggestions = []);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ─── Search ────────────────────────────────────────────────────────────────

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length >= 2 && _platform == 'Lichess') {
      _debounce = Timer(const Duration(milliseconds: 350), () async {
        final suggs = await _api.lichessAutocomplete(value.trim());
        if (mounted) setState(() => _liveSuggestions = suggs);
      });
    } else {
      if (mounted) setState(() => _liveSuggestions = []);
    }
  }

  // ─── Fetch ────────────────────────────────────────────────────────────────

  Future<void> _fetchStats({bool loadMore = false}) async {
    final username = _searchCtrl.text.trim();
    if (username.isEmpty) return;
    _searchFocus.unfocus();

    if (loadMore) {
      _loadedGamesCount += 10;
      setState(() => _isLoading = true);
    } else {
      _loadedGamesCount = 30;
      setState(() {
        _isLoading = true;
        _profile = null;
        _styleProfile = null;
        _games = [];
        _errorMessage = '';
      });
    }

    try {
      if (_platform == 'Lichess') {
        if (!loadMore) {
          _profile = await _api.fetchLichessProfile(username);
          if (_profile == null) _errorMessage = 'Lichess: Player not found.';
        }
        if (_profile != null) {
          _games = await _api.fetchLichessGames(username,
              tempo: _tempo == 'all' ? 'all' : _tempo,
              maxGames: _loadedGamesCount);
        }
      } else {
        if (!loadMore) {
          _profile = await _api.fetchChessComProfile(username);
          if (_profile == null) _errorMessage = 'Chess.com: Player not found.';
        }
        if (_profile != null) {
          _games = await _api.fetchChessComGames(username,
              tempo: _tempo == 'all' ? 'all' : _tempo,
              maxGames: _loadedGamesCount);
        }
      }

      if (_games.isNotEmpty && _profile != null) {
        _styleProfile =
            PlayerStyleAnalyzer.analyze(username, _games, _profile!.bestRating);
      }
    } catch (e) {
      _errorMessage = 'Connection failed. Try again.';
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final accent = widget.theme.lightTile;

    return Scaffold(
      backgroundColor: const Color(0xFF0E1420),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(accent),
            _buildSearchBar(accent),
            _buildTempoChips(accent),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: accent),
                    )
                  : _errorMessage.isNotEmpty && _profile == null
                      ? _buildError()
                      : _buildContent(accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.pop(context),
            child:
                Icon(Icons.arrow_back_ios_new_rounded, color: accent, size: 20),
          ),
          const SizedBox(width: 4),
          const Text(
            'Player Insights',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              fontFamily: 'Inter',
            ),
          ),
          const Spacer(),
          // Platform toggle
          _PlatformToggle(
            selected: _platform,
            accent: accent,
            onChanged: (p) {
              setState(() {
                _platform = p;
                _profile = null;
                _games = [];
                _styleProfile = null;
                _errorMessage = '';
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(Color accent) {
    final hasLinked = (widget.linkedLichessUser?.isNotEmpty ?? false) ||
        (widget.linkedChessComUser?.isNotEmpty ?? false);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CupertinoTextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            placeholder: 'Search username…',
            onChanged: _onSearchChanged,
            onSubmitted: (_) => _fetchStats(),
            autocorrect: false,
            style: const TextStyle(
                color: Colors.white, fontSize: 15, fontFamily: 'Inter'),
            placeholderStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 15,
                fontFamily: 'Inter'),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: accent.withValues(alpha: 0.2), width: 0.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            suffix: CupertinoButton(
              padding: const EdgeInsets.only(right: 8),
              minimumSize: Size.zero,
              onPressed: _fetchStats,
              child: Icon(Icons.search_rounded, color: accent, size: 22),
            ),
          ),
          // ── Quick linked account suggestions ──────────────────────────
          if (hasLinked &&
              _searchCtrl.text.isEmpty &&
              _liveSuggestions.isEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (widget.linkedLichessUser?.isNotEmpty ?? false)
                  _QuickSuggestChip(
                    icon: '♟',
                    label: widget.linkedLichessUser!,
                    accent: accent,
                    onTap: () {
                      _searchCtrl.text = widget.linkedLichessUser!;
                      setState(() => _platform = 'Lichess');
                      _fetchStats();
                    },
                  ),
                if (widget.linkedChessComUser?.isNotEmpty ?? false)
                  _QuickSuggestChip(
                    icon: '♞',
                    label: widget.linkedChessComUser!,
                    accent: const Color(0xFF6AAF6A),
                    onTap: () {
                      _searchCtrl.text = widget.linkedChessComUser!;
                      setState(() => _platform = 'Chess.com');
                      _fetchStats();
                    },
                  ),
              ],
            ),
          ],
          // Live autocomplete suggestions
          if (_liveSuggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF151E30),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: accent.withValues(alpha: 0.15), width: 0.5),
              ),
              child: Column(
                children: _liveSuggestions.take(5).map((s) {
                  return ListTile(
                    dense: true,
                    title: Text(s,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontFamily: 'Inter')),
                    onTap: () {
                      _searchCtrl.text = s;
                      setState(() => _liveSuggestions = []);
                      _fetchStats();
                    },
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTempoChips(Color accent) {
    final tempos = ['all', 'bullet', 'blitz', 'rapid', 'classical'];
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: tempos.length,
        itemBuilder: (_, i) {
          final t = tempos[i];
          final selected = _tempo == t;
          return GestureDetector(
            onTap: () {
              setState(() => _tempo = t);
              if (_profile != null) _fetchStats();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? accent.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              child: Text(
                t[0].toUpperCase() + t.substring(1),
                style: TextStyle(
                  color: selected ? accent : Colors.white70,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Text(
        _errorMessage,
        style: const TextStyle(
            color: Colors.redAccent, fontSize: 14, fontFamily: 'Inter'),
      ),
    );
  }

  Widget _buildContent(Color accent) {
    if (_profile == null) {
      return Center(
        child: Text(
          'Search for a player to see their insights.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 14,
            fontFamily: 'Inter',
          ),
        ),
      );
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // ── Profile card ────────────────────────────────────────────────
        _buildProfileCard(accent),

        // ── Style radar ─────────────────────────────────────────────────
        if (_styleProfile != null) ...[
          const SizedBox(height: 16),
          _buildStyleCard(accent),
        ],

        // ── Games list ──────────────────────────────────────────────────
        if (_games.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildGamesSection(accent),
        ],

        const SizedBox(height: 80),
      ],
    );
  }

  // ─── Profile Card ─────────────────────────────────────────────────────────

  Widget _buildProfileCard(Color accent) {
    final p = _profile!;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.18), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar placeholder
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  p.username.isNotEmpty ? p.username[0].toUpperCase() : '?',
                  style: TextStyle(
                      color: accent,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Inter'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (p.title.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFB300)
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              p.title,
                              style: const TextStyle(
                                  color: Color(0xFFFFB300),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'Inter'),
                            ),
                          ),
                        Text(
                          p.username,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Inter'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _platform,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12,
                          fontFamily: 'Inter'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _ratingChip('⚡', 'Bullet', p.bullet, accent),
              const SizedBox(width: 10),
              _ratingChip('🔥', 'Blitz', p.blitz, accent),
              const SizedBox(width: 10),
              _ratingChip('⏱', 'Rapid', p.rapid, accent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ratingChip(String icon, String label, int? rating, Color accent) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.15), width: 0.5),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              rating != null ? '$rating' : '—',
              style: TextStyle(
                  color: rating != null ? Colors.white : Colors.white38,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter'),
            ),
            Text(label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                    fontFamily: 'Inter')),
          ],
        ),
      ),
    );
  }

  // ─── Style Card ───────────────────────────────────────────────────────────

  Widget _buildStyleCard(Color accent) {
    final s = _styleProfile!;
    final dimensions = <String, int>{
      '🔥 Aggr': s.aggressive,
      '🛡️ Def': s.defensive,
      '⚔️ Tact': s.tactical,
      '🧠 Pos': s.positional,
      '🎯 Open': s.opening,
      '🎲 Risk': s.risk,
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.18), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(s.mainIcon, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.mainStyle,
                    style: TextStyle(
                        color: accent,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Inter'),
                  ),
                  if (s.subStyles.isNotEmpty)
                    Text(
                      s.subStyles.join('  ·  '),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 11,
                          fontFamily: 'Inter'),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...dimensions.entries
              .map((e) => _styleDimRow(e.key, e.value, accent)),
        ],
      ),
    );
  }

  Widget _styleDimRow(String label, int value, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11,
                  fontFamily: 'Inter'),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value / 100.0,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor:
                    AlwaysStoppedAnimation(accent.withValues(alpha: 0.8)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$value',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter'),
          ),
        ],
      ),
    );
  }

  // ─── Games Section ────────────────────────────────────────────────────────

  Widget _buildGamesSection(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'RECENT GAMES  (${_games.length})',
            style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                fontFamily: 'Inter'),
          ),
        ),
        ...List.generate(
          _games.length,
          (i) => GameHistoryTile(
            game: _games[i],
            theme: widget.theme,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GameAnalysisPage(game: _games[i]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Load more button
        if (_games.length >= _loadedGamesCount)
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              onPressed: _isLoading ? null : () => _fetchStats(loadMore: true),
              padding: EdgeInsets.zero,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: accent.withValues(alpha: 0.25), width: 0.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Load more',
                  style: TextStyle(
                      color: accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Inter'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Platform Toggle ──────────────────────────────────────────────────────────

class _PlatformToggle extends StatelessWidget {
  final String selected;
  final Color accent;
  final ValueChanged<String> onChanged;

  const _PlatformToggle({
    required this.selected,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: ['Lichess', 'Chess.com'].map((p) {
          final isSelected = selected == p;
          return GestureDetector(
            onTap: () => onChanged(p),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? accent.withValues(alpha: 0.22)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: isSelected
                    ? Border.all(
                        color: accent.withValues(alpha: 0.5), width: 0.5)
                    : null,
              ),
              child: Text(
                p,
                style: TextStyle(
                  color: isSelected ? accent : Colors.white54,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Quick Suggest Chip ───────────────────────────────────────────────────────

class _QuickSuggestChip extends StatelessWidget {
  final String icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _QuickSuggestChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: TextStyle(color: accent, fontSize: 13)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward_ios_rounded,
                color: accent.withValues(alpha: 0.5), size: 10),
          ],
        ),
      ),
    );
  }
}
