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

  // ── Profile / Stats ──
  int userRating = 1200;
  List<int> beatenBots = [];
  String userName = 'Player';
  String userAvatar = 'king_white';

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
    userRating = _prefs!.getInt('userRating') ?? 1200;
    beatenBots =
        (_prefs!.getStringList('beatenBots') ?? []).map(int.parse).toList();
    userName = _prefs!.getString('userName') ?? 'Player';
    userAvatar = _prefs!.getString('userAvatar') ?? 'king_white';
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

  Future<void> setUserRating(int rating) async {
    userRating = rating;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt('userRating', rating);
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

  Future<void> resetStats() async {
    userRating = 1200;
    beatenBots = [];
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt('userRating', userRating);
    await _prefs!.setStringList('beatenBots', []);
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
    // Note: profile stats (rating, beatenBots, userName, userAvatar) are NOT
    // reset by this method — only via resetStats().
    onChanged?.call();
  }
}
