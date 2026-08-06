import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../model/app_model.dart';
import '../../../model/app_themes.dart';

/// Settings section for linking Lichess and Chess.com accounts.
/// Displays two text fields; changes are debounced 150 ms and persisted
/// via AppModel → UserPreferences → SharedPreferences.
class LinkedAccountsSection extends StatefulWidget {
  const LinkedAccountsSection({Key? key}) : super(key: key);

  @override
  State<LinkedAccountsSection> createState() => _LinkedAccountsSectionState();
}

class _LinkedAccountsSectionState extends State<LinkedAccountsSection> {
  late final TextEditingController _lichessCtrl;
  late final TextEditingController _chessComCtrl;
  bool _lichessSynced = false;
  bool _chessComSynced = false;

  @override
  void initState() {
    super.initState();
    final appModel = context.read<AppModel>();
    _lichessCtrl = TextEditingController(text: appModel.lichessUsername);
    _chessComCtrl = TextEditingController(text: appModel.chessComUsername);
    _lichessSynced = appModel.lichessUsername.isNotEmpty;
    _chessComSynced = appModel.chessComUsername.isNotEmpty;
  }

  @override
  void dispose() {
    _lichessCtrl.dispose();
    _chessComCtrl.dispose();
    super.dispose();
  }

  void _syncLichess(AppModel appModel) {
    appModel.setLichessUsername(_lichessCtrl.text.trim());
    setState(() => _lichessSynced = _lichessCtrl.text.trim().isNotEmpty);
  }

  void _syncChessCom(AppModel appModel) {
    appModel.setChessComUsername(_chessComCtrl.text.trim());
    setState(() => _chessComSynced = _chessComCtrl.text.trim().isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AppModel, AppTheme>(
      selector: (_, m) => m.theme,
      builder: (context, theme, _) {
        final appModel = context.read<AppModel>();
        final accent = theme.lightTile;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(
                  left: 16, top: 20, bottom: 8, right: 16),
              child: Row(
                children: [
                  Icon(Icons.link_rounded, color: accent, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'LINKED ACCOUNTS',
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),

            // ── Card ────────────────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: accent.withValues(alpha: 0.12),
                  width: 0.5,
                ),
              ),
              child: Column(
                children: [
                  _AccountRow(
                    icon: '♟',
                    label: 'Lichess',
                    hint: 'username',
                    controller: _lichessCtrl,
                    accent: accent,
                    isSynced: _lichessSynced,
                    onSync: () => _syncLichess(appModel),
                    onChanged: (_) => setState(() => _lichessSynced = false),
                    onClear: () {
                      _lichessCtrl.clear();
                      appModel.setLichessUsername('');
                      setState(() => _lichessSynced = false);
                    },
                  ),
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: accent.withValues(alpha: 0.08),
                  ),
                  _AccountRow(
                    icon: '♞',
                    label: 'Chess.com',
                    hint: 'username',
                    controller: _chessComCtrl,
                    accent: accent,
                    isSynced: _chessComSynced,
                    onSync: () => _syncChessCom(appModel),
                    onChanged: (_) => setState(() => _chessComSynced = false),
                    onClear: () {
                      _chessComCtrl.clear();
                      appModel.setChessComUsername('');
                      setState(() => _chessComSynced = false);
                    },
                  ),
                ],
              ),
            ),

            // ── Info text ───────────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.only(left: 20, top: 6, bottom: 4, right: 16),
              child: Text(
                'Connect your accounts to see your game history and analyse your play on the Analysis tab.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.38),
                  fontSize: 11,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Single Account Row ────────────────────────────────────────────────────────

class _AccountRow extends StatelessWidget {
  final String icon;
  final String label;
  final String hint;
  final TextEditingController controller;
  final Color accent;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onSync;
  final bool isSynced;

  const _AccountRow({
    required this.icon,
    required this.label,
    required this.hint,
    required this.controller,
    required this.accent,
    required this.onChanged,
    required this.onClear,
    required this.onSync,
    required this.isSynced,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Platform icon + label
          SizedBox(
            width: 90,
            child: Row(
              children: [
                Text(
                  icon,
                  style: TextStyle(
                    color: accent,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Inter',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Text input
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              placeholder: hint,
              onChanged: onChanged,
              onSubmitted: (_) => onSync(),
              autocorrect: false,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_\-]')),
              ],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontFamily: 'Inter',
              ),
              placeholderStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 14,
                fontFamily: 'Inter',
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSynced
                      ? const Color(0xFF4CAF50).withValues(alpha: 0.4)
                      : accent.withValues(alpha: 0.15),
                  width: isSynced ? 1.0 : 0.5,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            ),
          ),
          const SizedBox(width: 6),

          // Sync / Synced button
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) {
              if (value.text.isEmpty) return const SizedBox(width: 0);
              if (isSynced) {
                return Icon(
                  Icons.check_circle_rounded,
                  color: const Color(0xFF4CAF50),
                  size: 22,
                );
              }
              return CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: onSync,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: accent.withValues(alpha: 0.4), width: 0.5),
                  ),
                  child: Text(
                    'Sync',
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              );
            },
          ),

          // Clear button
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) {
              if (value.text.isEmpty) return const SizedBox(width: 0);
              return CupertinoButton(
                padding: const EdgeInsets.only(left: 4),
                minimumSize: Size.zero,
                onPressed: onClear,
                child: Icon(
                  Icons.cancel_rounded,
                  color: Colors.white.withValues(alpha: 0.25),
                  size: 16,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
