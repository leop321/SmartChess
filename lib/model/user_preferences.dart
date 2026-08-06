import 'package:shared_preferences/shared_preferences.dart';

import 'app_themes.dart';

const PIECE_THEMES = [
  'Classic',
  'Angular',
  '8-Bit',
  'Letters',
  'Old School',
  'Fairy Tale'
];

final List<String> sortedPieceThemes = () {
  var list = List<String>.from(PIECE_THEMES);
  list.sort();
  return list;
}();

/// Manages user preferences backed by SharedPreferences.
/// Extracted from AppModel to follow single-responsibility principle.
class UserPreferences {
  SharedPreferences? _prefs;

  String pieceTheme = 'Classic';
  String themeName = 'Forest Mint';
  bool showMoveHistory = true;
  bool allowUndoRedo = true;
  bool soundEnabled = true;
  bool showHints = true;
  bool showNotation = false;
  bool enableRotation = true;
  bool enablePieceRotation = true;
  bool hapticEnabled = false;
  String aiEngine = 'stockfish';
  int timerIncrement = 0;
  String timerMode = 'increment';
  bool ttsEnabled = false;
  double ttsSpeechRate = 0.5;
  double ttsPitch = 1.0;

  // ── Linked Accounts (Analysis feature) ──
  String lichessUsername = '';
  String chessComUsername = '';

  // ── Profile / Stats ──
  int userRatingNormal = 1200;
  int userRatingBlind = 1200;
  List<int> beatenBots = [];
  List<int> beatenBotsBlind = [];
  String userName = 'Player';
  String userAvatar = 'king_white';

  // ── Rating Change & Adjustment Cooldown Tracking (Normal) ──
  int lastGameRatingChangeNormal = 0;
  String lastGameDateNormal = '';
  int todayRatingChangeNormal = 0;
  int ratingAdjustmentsCountNormal = 0;
  int lastAdjustmentTimestampNormal = 0;

  // ── Rating Change & Adjustment Cooldown Tracking (Blind) ──
  int lastGameRatingChangeBlind = 0;
  String lastGameDateBlind = '';
  int todayRatingChangeBlind = 0;
  int ratingAdjustmentsCountBlind = 0;
  int lastAdjustmentTimestampBlind = 0;

  List<String> get pieceThemes => sortedPieceThemes;

  AppTheme get theme {
    return themeList[themeIndex];
  }

  int get themeIndex {
    var idx = themeList.indexWhere((theme) => theme.name == themeName);
    return idx >= 0 ? idx : 0;
  }

  int get pieceThemeIndex {
    var idx = pieceThemes.indexWhere((theme) => theme == pieceTheme);
    return idx >= 0 ? idx : 0;
  }

  /// Called after any preference changes.
  void Function()? onChanged;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    themeName = _prefs!.getString('themeName') ?? 'Forest Mint';
    pieceTheme = _prefs!.getString('pieceTheme') ?? 'Classic';
    showMoveHistory = _prefs!.getBool('showMoveHistory') ?? true;
    soundEnabled = _prefs!.getBool('soundEnabled') ?? true;
    showHints = _prefs!.getBool('showHints') ?? true;
    showNotation = _prefs!.getBool('showNotation') ?? false;
    enableRotation = _prefs!.getBool('enableRotation') ?? true;
    enablePieceRotation = _prefs!.getBool('enablePieceRotation') ?? true;
    allowUndoRedo = _prefs!.getBool('allowUndoRedo') ?? true;
    hapticEnabled = _prefs!.getBool('hapticEnabled') ?? false;
    aiEngine = 'stockfish';
    _prefs!.setString('aiEngine', 'stockfish');
    timerIncrement = _prefs!.getInt('timerIncrement') ?? 0;
    timerMode = _prefs!.getString('timerMode') ?? 'increment';
    ttsEnabled = _prefs!.getBool('ttsEnabled') ?? false;
    ttsSpeechRate = _prefs!.getDouble('ttsSpeechRate') ?? 0.5;
    ttsPitch = _prefs!.getDouble('ttsPitch') ?? 1.0;
    lichessUsername = _prefs!.getString('lichessUsername') ?? '';
    chessComUsername = _prefs!.getString('chessComUsername') ?? '';
    userRatingNormal = _prefs!.getInt('userRatingNormal') ??
        _prefs!.getInt('userRating') ??
        1200;
    userRatingBlind = _prefs!.getInt('userRatingBlind') ?? 1200;
    beatenBots =
        (_prefs!.getStringList('beatenBots') ?? []).map(int.parse).toList();
    beatenBotsBlind = (_prefs!.getStringList('beatenBotsBlind') ?? [])
        .map(int.parse)
        .toList();
    userName = _prefs!.getString('userName') ?? 'Player';

    userAvatar = _prefs!.getString('userAvatar') ?? 'king_white';

    lastGameRatingChangeNormal = _prefs!.getInt('lastGameRatingChangeNormal') ??
        _prefs!.getInt('lastGameRatingChange') ??
        0;
    lastGameDateNormal = _prefs!.getString('lastGameDateNormal') ??
        _prefs!.getString('lastGameDate') ??
        '';
    todayRatingChangeNormal = _prefs!.getInt('todayRatingChangeNormal') ??
        _prefs!.getInt('todayRatingChange') ??
        0;
    ratingAdjustmentsCountNormal =
        _prefs!.getInt('ratingAdjustmentsCountNormal') ??
            _prefs!.getInt('ratingAdjustmentsCount') ??
            0;
    lastAdjustmentTimestampNormal =
        _prefs!.getInt('lastAdjustmentTimestampNormal') ??
            _prefs!.getInt('lastAdjustmentTimestamp') ??
            0;

    lastGameRatingChangeBlind =
        _prefs!.getInt('lastGameRatingChangeBlind') ?? 0;
    lastGameDateBlind = _prefs!.getString('lastGameDateBlind') ?? '';
    todayRatingChangeBlind = _prefs!.getInt('todayRatingChangeBlind') ?? 0;
    ratingAdjustmentsCountBlind =
        _prefs!.getInt('ratingAdjustmentsCountBlind') ?? 0;
    lastAdjustmentTimestampBlind =
        _prefs!.getInt('lastAdjustmentTimestampBlind') ?? 0;

    onChanged?.call();
  }

  Future<void> setTheme(int index) async {
    themeName = themeList[index].name ?? "";
    onChanged?.call();
    _prefs ??= await SharedPreferences.getInstance();
    _prefs!.setString('themeName', themeName);
  }

  Future<void> setPieceTheme(int index) async {
    pieceTheme = pieceThemes[index];
    onChanged?.call();
    _prefs ??= await SharedPreferences.getInstance();
    _prefs!.setString('pieceTheme', pieceTheme);
  }

  Future<void> setShowMoveHistory(bool show) async {
    showMoveHistory = show;
    _prefs ??= await SharedPreferences.getInstance();
    _prefs!.setBool('showMoveHistory', show);
    onChanged?.call();
  }

  Future<void> setSoundEnabled(bool enabled) async {
    soundEnabled = enabled;
    _prefs ??= await SharedPreferences.getInstance();
    _prefs!.setBool('soundEnabled', enabled);
    onChanged?.call();
  }

  Future<void> setShowHints(bool show) async {
    showHints = show;
    _prefs ??= await SharedPreferences.getInstance();
    _prefs!.setBool('showHints', show);
    onChanged?.call();
  }

  Future<void> setShowNotation(bool show) async {
    showNotation = show;
    _prefs ??= await SharedPreferences.getInstance();
    _prefs!.setBool('showNotation', show);
    onChanged?.call();
  }

  Future<void> setEnableRotation(bool enable) async {
    enableRotation = enable;
    _prefs ??= await SharedPreferences.getInstance();
    _prefs!.setBool('enableRotation', enable);
    onChanged?.call();
  }

  Future<void> setEnablePieceRotation(bool enable) async {
    enablePieceRotation = enable;
    _prefs ??= await SharedPreferences.getInstance();
    _prefs!.setBool('enablePieceRotation', enable);
    onChanged?.call();
  }

  Future<void> setAllowUndoRedo(bool allow) async {
    allowUndoRedo = allow;
    _prefs ??= await SharedPreferences.getInstance();
    _prefs!.setBool('allowUndoRedo', allow);
    onChanged?.call();
  }

  Future<void> setHapticEnabled(bool enabled) async {
    hapticEnabled = enabled;
    _prefs ??= await SharedPreferences.getInstance();
    _prefs!.setBool('hapticEnabled', enabled);
    onChanged?.call();
  }

  Future<void> setTimerIncrement(int increment) async {
    timerIncrement = increment;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt('timerIncrement', increment);
    onChanged?.call();
  }

  Future<void> setTimerMode(String mode) async {
    timerMode = mode;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString('timerMode', mode);
    onChanged?.call();
  }

  Future<void> setUserRating(int rating, bool isBlind) async {
    _prefs ??= await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    if (isBlind) {
      final oldRating = userRatingBlind;
      userRatingBlind = rating;
      final change = rating - oldRating;
      if (change != 0) {
        lastGameRatingChangeBlind = change;
        if (lastGameDateBlind == todayStr) {
          todayRatingChangeBlind += change;
        } else {
          todayRatingChangeBlind = change;
          lastGameDateBlind = todayStr;
        }
        await _prefs!
            .setInt('lastGameRatingChangeBlind', lastGameRatingChangeBlind);
        await _prefs!.setString('lastGameDateBlind', lastGameDateBlind);
        await _prefs!.setInt('todayRatingChangeBlind', todayRatingChangeBlind);
      }
      await _prefs!.setInt('userRatingBlind', rating);
    } else {
      final oldRating = userRatingNormal;
      userRatingNormal = rating;
      final change = rating - oldRating;
      if (change != 0) {
        lastGameRatingChangeNormal = change;
        if (lastGameDateNormal == todayStr) {
          todayRatingChangeNormal += change;
        } else {
          todayRatingChangeNormal = change;
          lastGameDateNormal = todayStr;
        }
        await _prefs!
            .setInt('lastGameRatingChangeNormal', lastGameRatingChangeNormal);
        await _prefs!.setString('lastGameDateNormal', lastGameDateNormal);
        await _prefs!
            .setInt('todayRatingChangeNormal', todayRatingChangeNormal);
      }
      await _prefs!.setInt('userRatingNormal', rating);
    }
    onChanged?.call();
  }

  Future<void> adjustUserRating(int rating, bool isBlind) async {
    _prefs ??= await SharedPreferences.getInstance();
    if (isBlind) {
      userRatingBlind = rating;
      ratingAdjustmentsCountBlind++;
      lastAdjustmentTimestampBlind = DateTime.now().millisecondsSinceEpoch;
      await _prefs!.setInt('userRatingBlind', rating);
      await _prefs!
          .setInt('ratingAdjustmentsCountBlind', ratingAdjustmentsCountBlind);
      await _prefs!
          .setInt('lastAdjustmentTimestampBlind', lastAdjustmentTimestampBlind);
    } else {
      userRatingNormal = rating;
      ratingAdjustmentsCountNormal++;
      lastAdjustmentTimestampNormal = DateTime.now().millisecondsSinceEpoch;
      await _prefs!.setInt('userRatingNormal', rating);
      await _prefs!
          .setInt('ratingAdjustmentsCountNormal', ratingAdjustmentsCountNormal);
      await _prefs!.setInt(
          'lastAdjustmentTimestampNormal', lastAdjustmentTimestampNormal);
    }
    onChanged?.call();
  }

  Future<void> resetRatingAdjustmentsCount(bool isBlind) async {
    _prefs ??= await SharedPreferences.getInstance();
    if (isBlind) {
      ratingAdjustmentsCountBlind = 0;
      await _prefs!.setInt('ratingAdjustmentsCountBlind', 0);
    } else {
      ratingAdjustmentsCountNormal = 0;
      await _prefs!.setInt('ratingAdjustmentsCountNormal', 0);
    }
    onChanged?.call();
  }

  Future<void> addBeatenBot(int difficulty) async {
    if (!beatenBots.contains(difficulty)) {
      beatenBots = List<int>.from(beatenBots)..add(difficulty);
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setStringList(
          'beatenBots', beatenBots.map((e) => e.toString()).toList());
      onChanged?.call();
    }
  }

  Future<void> addBeatenBotBlind(int difficulty) async {
    if (!beatenBotsBlind.contains(difficulty)) {
      beatenBotsBlind = List<int>.from(beatenBotsBlind)..add(difficulty);
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setStringList(
          'beatenBotsBlind', beatenBotsBlind.map((e) => e.toString()).toList());
      onChanged?.call();
    }
  }

  Future<void> resetStats() async {
    userRatingNormal = 1200;
    userRatingBlind = 1200;
    beatenBots = [];
    beatenBotsBlind = [];
    lastGameRatingChangeNormal = 0;

    lastGameDateNormal = '';
    todayRatingChangeNormal = 0;
    ratingAdjustmentsCountNormal = 0;
    lastAdjustmentTimestampNormal = 0;

    lastGameRatingChangeBlind = 0;
    lastGameDateBlind = '';
    todayRatingChangeBlind = 0;
    ratingAdjustmentsCountBlind = 0;
    lastAdjustmentTimestampBlind = 0;

    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt('userRatingNormal', userRatingNormal);
    await _prefs!.setInt('userRatingBlind', userRatingBlind);
    await _prefs!.setStringList('beatenBots', []);
    await _prefs!.setStringList('beatenBotsBlind', []);

    await _prefs!.setInt('lastGameRatingChangeNormal', 0);
    await _prefs!.setString('lastGameDateNormal', '');
    await _prefs!.setInt('todayRatingChangeNormal', 0);
    await _prefs!.setInt('ratingAdjustmentsCountNormal', 0);
    await _prefs!.setInt('lastAdjustmentTimestampNormal', 0);

    await _prefs!.setInt('lastGameRatingChangeBlind', 0);
    await _prefs!.setString('lastGameDateBlind', '');
    await _prefs!.setInt('todayRatingChangeBlind', 0);
    await _prefs!.setInt('ratingAdjustmentsCountBlind', 0);
    await _prefs!.setInt('lastAdjustmentTimestampBlind', 0);
    onChanged?.call();
  }

  Future<void> setUserName(String name) async {
    userName = name;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString('userName', name);
    onChanged?.call();
  }

  Future<void> setUserAvatar(String avatar) async {
    userAvatar = avatar;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString('userAvatar', avatar);
    onChanged?.call();
  }

  Future<void> setLichessUsername(String name) async {
    lichessUsername = name.trim();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString('lichessUsername', lichessUsername);
    onChanged?.call();
  }

  Future<void> setChessComUsername(String name) async {
    chessComUsername = name.trim();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString('chessComUsername', chessComUsername);
    onChanged?.call();
  }

  Future<void> setTtsEnabled(bool enabled) async {
    ttsEnabled = enabled;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool('ttsEnabled', enabled);
    onChanged?.call();
  }

  Future<void> setTtsSpeechRate(double rate) async {
    ttsSpeechRate = rate;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setDouble('ttsSpeechRate', rate);
    onChanged?.call();
  }

  Future<void> setTtsPitch(double pitch) async {
    ttsPitch = pitch;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setDouble('ttsPitch', pitch);
    onChanged?.call();
  }

  Future<void> resetToDefaults() async {
    themeName = 'Forest Mint';
    pieceTheme = 'Classic';
    showMoveHistory = true;
    soundEnabled = true;
    showHints = true;
    showNotation = false;
    enableRotation = true;
    enablePieceRotation = true;
    allowUndoRedo = true;
    hapticEnabled = false;
    aiEngine = 'stockfish';
    timerIncrement = 0;
    timerMode = 'increment';
    ttsEnabled = false;
    ttsSpeechRate = 0.5;
    ttsPitch = 1.0;

    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString('themeName', themeName);
    await _prefs!.setString('pieceTheme', pieceTheme);
    await _prefs!.setBool('showMoveHistory', showMoveHistory);
    await _prefs!.setBool('soundEnabled', soundEnabled);
    await _prefs!.setBool('showHints', showHints);
    await _prefs!.setBool('showNotation', showNotation);
    await _prefs!.setBool('enableRotation', enableRotation);
    await _prefs!.setBool('enablePieceRotation', enablePieceRotation);
    await _prefs!.setBool('allowUndoRedo', allowUndoRedo);
    await _prefs!.setBool('hapticEnabled', hapticEnabled);
    await _prefs!.setString('aiEngine', aiEngine);
    await _prefs!.setInt('timerIncrement', timerIncrement);
    await _prefs!.setString('timerMode', timerMode);
    await _prefs!.setBool('ttsEnabled', ttsEnabled);
    await _prefs!.setDouble('ttsSpeechRate', ttsSpeechRate);
    await _prefs!.setDouble('ttsPitch', ttsPitch);
    // Note: profile stats (rating, beatenBots, userName, userAvatar) are NOT
    // reset by this method — only via resetStats().
    onChanged?.call();
  }
}
