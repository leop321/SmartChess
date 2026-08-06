import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../model/app_themes.dart';
import '../analyze_view/game_analysis_page.dart';

/// Bottom sheet for selecting the source of a game to analyse.
/// Offers: PGN/FEN paste, search from API (Lichess/Chess.com), or library.
class AnalyzeGameBottomSheet extends StatefulWidget {
  final AppTheme theme;

  const AnalyzeGameBottomSheet({Key? key, required this.theme})
      : super(key: key);

  static Future<void> show(BuildContext context, AppTheme theme) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AnalyzeGameBottomSheet(theme: theme),
    );
  }

  @override
  State<AnalyzeGameBottomSheet> createState() => _AnalyzeGameBottomSheetState();
}

class _AnalyzeGameBottomSheetState extends State<AnalyzeGameBottomSheet> {
  final _pgnCtrl = TextEditingController();
  bool _pgnMode = false;
  bool _isPgnValid = false;

  @override
  void dispose() {
    _pgnCtrl.dispose();
    super.dispose();
  }

  void _onPgnChanged(String value) {
    setState(() {
      _isPgnValid = _validatePgn(value);
    });
  }

  bool _validatePgn(String pgn) {
    final trimmed = pgn.trim();
    if (trimmed.isEmpty) return false;
    // Accept any non-empty input — real validation happens in the chess engine.
    // A PGN has move numbers (1.) or piece moves, a FEN has '/' separators.
    return trimmed.length > 3;
  }

  void _analyzeFromPgn() {
    final pgn = _pgnCtrl.text.trim();
    if (!_isPgnValid) return;
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameAnalysisPage(pgn: pgn),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.theme.lightTile;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111928),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Handle ─────────────────────────────────────────────────
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

              // ── Title ──────────────────────────────────────────────────
              Text(
                'Analyse a Game',
                style: TextStyle(
                  color: accent,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose how to load the game.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 13,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 20),

              // ── Options ────────────────────────────────────────────────
              if (!_pgnMode) ...[
                _OptionTile(
                  icon: Icons.content_paste_rounded,
                  label: 'Paste PGN / FEN',
                  subtitle: 'Analyse from clipboard or manual input',
                  accent: accent,
                  onTap: () => setState(() => _pgnMode = true),
                ),
                const SizedBox(height: 10),
                _OptionTile(
                  icon: Icons.search_rounded,
                  label: 'From Lichess / Chess.com',
                  subtitle: 'Browse your account games',
                  accent: accent,
                  onTap: () {
                    Navigator.pop(context);
                    // Player Insights page already allows opening games
                  },
                ),
                const SizedBox(height: 10),
                _OptionTile(
                  icon: Icons.bookmark_outline_rounded,
                  label: 'From Library',
                  subtitle: 'Your saved analyses',
                  accent: accent,
                  onTap: () => Navigator.pop(context),
                ),
              ] else ...[
                // ── PGN input ────────────────────────────────────────────
                CupertinoTextField(
                  controller: _pgnCtrl,
                  placeholder:
                      'Paste PGN or FEN here…\n\ne.g. 1. e4 e5 2. Nf3 Nc6 3. Bb5',
                  onChanged: _onPgnChanged,
                  maxLines: 8,
                  autocorrect: false,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontFamily: 'Inter',
                  ),
                  placeholderStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 13,
                    fontFamily: 'Inter',
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: accent.withValues(alpha: 0.2), width: 0.5),
                  ),
                  padding: const EdgeInsets.all(14),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        onPressed: () => setState(() => _pgnMode = false),
                        padding: EdgeInsets.zero,
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'Back',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: CupertinoButton(
                        onPressed: _isPgnValid ? _analyzeFromPgn : null,
                        padding: EdgeInsets.zero,
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: _isPgnValid
                                ? LinearGradient(colors: [
                                    accent.withValues(alpha: 0.85),
                                    accent.withValues(alpha: 0.6),
                                  ])
                                : null,
                            color: _isPgnValid
                                ? null
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Analyse',
                            style: TextStyle(
                              color:
                                  _isPgnValid ? Colors.white : Colors.white30,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Option Tile ──────────────────────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.08), width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.25),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
