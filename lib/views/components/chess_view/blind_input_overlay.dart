import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as prov;

import '../../../logic/game_controller.dart';
import '../../../logic/game_mode_notifier.dart';
import '../../../logic/peeking_notifier.dart';
import '../../../model/app_model.dart';
import '../../../model/app_themes.dart';
import '../../../model/player.dart';
import '../shared/glass_panel.dart';

/// Full-width bottom overlay that replaces board taps in Blind / Snapshot modes.
///
/// Input flow:
///   Piece selector → File (a–h) → Rank (1–8) → auto-submit via [GameController.submitBlindMove].
///
/// Action buttons:
///   "Peek" — consume one token to reveal board for 1.5 s.
///   "Update Board" (Snapshot only) — sync frozen visual to engine state.
class BlindInputOverlay extends ConsumerStatefulWidget {
  final GameController controller;
  const BlindInputOverlay({Key? key, required this.controller})
      : super(key: key);

  @override
  ConsumerState<BlindInputOverlay> createState() => _BlindInputOverlayState();
}

class _BlindInputOverlayState extends ConsumerState<BlindInputOverlay>
    with SingleTickerProviderStateMixin {
  // Current partial move being assembled: e.g. "e" then "e2" then "e2e4"
  String _fromFile = '';
  String _fromRank = '';
  String _toFile = '';
  // Input step: 0=from-file, 1=from-rank, 2=to-file, 3=to-rank
  int _step = 0;
  String? _errorMessage;
  bool _showError = false;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnim = Tween<double>(begin: 0, end: 8)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeCtrl);
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _reset({String? error}) {
    setState(() {
      _fromFile = '';
      _fromRank = '';
      _toFile = '';
      _step = 0;
      if (error != null) {
        _errorMessage = error;
        _showError = true;
      }
    });
    if (error != null) {
      _shakeCtrl.forward(from: 0);
      Future.delayed(const Duration(milliseconds: 1800),
          () => mounted ? setState(() => _showError = false) : null);
    }
  }

  void _handleFile(String file) {
    setState(() {
      if (_step == 0) {
        _fromFile = file;
        _step = 1;
      } else if (_step == 2) {
        _toFile = file;
        _step = 3;
      }
    });
  }

  void _handleRank(String rank) {
    if (_step == 1) {
      setState(() {
        _fromRank = rank;
        _step = 2;
      });
    } else if (_step == 3) {
      final move = '$_fromFile$_fromRank$_toFile$rank';
      final ok = widget.controller.submitBlindMove(move);
      if (ok) {
        _reset();
      } else {
        _reset(error: 'Illegal move: $move');
      }
    }
  }

  String get _partialDisplay {
    if (_step == 0) return '___';
    if (_step == 1) return '${_fromFile}__';
    if (_step == 2) return '$_fromFile$_fromRank → ___';
    return '$_fromFile$_fromRank → ${_toFile}_';
  }

  @override
  Widget build(BuildContext context) {
    final appModel = prov.Provider.of<AppModel>(context, listen: false);
    final theme = appModel.theme;
    final mode = appModel.gameMode;
    final peekState = ref.watch(peekingProvider);
    final isWhiteTurn = appModel.turn == Player.player1;
    final tokens =
        isWhiteTurn ? peekState.player1Tokens : peekState.player2Tokens;

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedSlide(
        offset: const Offset(0, 0),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        child: GlassPanel(
          borderRadius: 24,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          color: theme.darkTile.withValues(alpha: 0.72),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drag handle ─────────────────────────────────────
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // ── Status row ──────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Mode badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.moveHint.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      mode == ChessMode.blind ? 'BLIND' : 'SNAPSHOT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: theme.lightTile,
                      ),
                    ),
                  ),

                  // Partial move display
                  AnimatedBuilder(
                    animation: _shakeAnim,
                    builder: (_, child) => Transform.translate(
                      offset: Offset(
                          _showError
                              ? _shakeAnim.value *
                                  ((_shakeCtrl.value < 0.5) ? 1 : -1)
                              : 0,
                          0),
                      child: child,
                    ),
                    child: Text(
                      _showError ? (_errorMessage ?? '') : _partialDisplay,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                        color: _showError
                            ? const Color(0xFFFF5252)
                            : const Color(0xFFE5E2E1),
                        letterSpacing: 2,
                      ),
                    ),
                  ),

                  // Token counter
                  Row(
                    children: [
                      Icon(Icons.visibility_outlined,
                          size: 14,
                          color: theme.lightTile.withValues(alpha: 0.7)),
                      const SizedBox(width: 4),
                      Text(
                        '$tokens',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: tokens > 0
                              ? const Color(0xFF4CAF50)
                              : theme.lightTile.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ── Step label ──────────────────────────────────────
              Text(
                _stepLabel(),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.lightTile.withValues(alpha: 0.55),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),

              // ── File row (a–h) — shown on step 0 and 2 ─────────
              if (_step == 0 || _step == 2)
                _KeyRow(
                  keys: const ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'],
                  theme: theme,
                  onKey: _handleFile,
                ),

              // ── Rank row (1–8) — shown on step 1 and 3 ─────────
              if (_step == 1 || _step == 3)
                _KeyRow(
                  keys: const ['1', '2', '3', '4', '5', '6', '7', '8'],
                  theme: theme,
                  onKey: _handleRank,
                ),

              const SizedBox(height: 10),

              // ── Back + action buttons ────────────────────────────
              Row(
                children: [
                  // Back / Clear
                  if (_step > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _ActionButton(
                        icon: Icons.backspace_outlined,
                        label: 'Back',
                        theme: theme,
                        onTap: () => setState(() {
                          if (_step > 0) _step--;
                          if (_step == 0) _fromFile = '';
                          if (_step == 1) _fromRank = '';
                          if (_step == 2) _toFile = '';
                        }),
                      ),
                    ),

                  const Spacer(),

                  // Peek
                  _ActionButton(
                    icon: Icons.visibility_outlined,
                    label: 'Peek ($tokens)',
                    theme: theme,
                    enabled: tokens > 0,
                    onTap: () {
                      appModel.haptic.light();
                      widget.controller.peekBoard();
                    },
                  ),
                  const SizedBox(width: 8),

                  // Update Board (Snapshot only)
                  if (mode == ChessMode.snapshot)
                    _ActionButton(
                      icon: Icons.sync_rounded,
                      label: 'Update',
                      theme: theme,
                      onTap: () {
                        appModel.haptic.light();
                        widget.controller.updateBoard();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  String _stepLabel() {
    switch (_step) {
      case 0:
        return 'From — select file (a–h)';
      case 1:
        return 'From — select rank (1–8)';
      case 2:
        return 'To — select file (a–h)';
      case 3:
        return 'To — select rank (1–8)';
      default:
        return '';
    }
  }
}

// ─────────────────────────────────────────────────────
// Keyboard row widget
// ─────────────────────────────────────────────────────
class _KeyRow extends StatelessWidget {
  final List<String> keys;
  final AppTheme theme;
  final void Function(String) onKey;

  const _KeyRow({
    required this.keys,
    required this.theme,
    required this.onKey,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: keys
          .map((k) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: GestureDetector(
                    onTap: () => onKey(k),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      height: 44,
                      decoration: BoxDecoration(
                        color: theme.darkTile.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.lightTile.withValues(alpha: 0.18),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        k,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: theme.lightTile,
                        ),
                      ),
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }
}

// ─────────────────────────────────────────────────────
// Action button (Peek / Update / Back)
// ─────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final AppTheme theme;
  final VoidCallback onTap;
  final bool enabled;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.theme,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        enabled ? theme.lightTile : theme.lightTile.withValues(alpha: 0.3);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: enabled
              ? theme.moveHint.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
