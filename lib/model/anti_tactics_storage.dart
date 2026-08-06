import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AntiTacticsStats {
  final int attempted;
  final int solved;
  final int noTacticCorrect;
  final int winningTacticCorrect;
  final int wrongAnswers;
  final int currentStreak;
  final int bestStreak;

  const AntiTacticsStats({
    this.attempted = 0,
    this.solved = 0,
    this.noTacticCorrect = 0,
    this.winningTacticCorrect = 0,
    this.wrongAnswers = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
  });

  double get accuracy => attempted == 0 ? 0.0 : solved / attempted;

  factory AntiTacticsStats.fromJson(Map<String, dynamic> json) {
    return AntiTacticsStats(
      attempted: json['attempted'] ?? 0,
      solved: json['solved'] ?? 0,
      noTacticCorrect: json['noTacticCorrect'] ?? 0,
      winningTacticCorrect: json['winningTacticCorrect'] ?? 0,
      wrongAnswers: json['wrongAnswers'] ?? 0,
      currentStreak: json['currentStreak'] ?? 0,
      bestStreak: json['bestStreak'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'attempted': attempted,
        'solved': solved,
        'noTacticCorrect': noTacticCorrect,
        'winningTacticCorrect': winningTacticCorrect,
        'wrongAnswers': wrongAnswers,
        'currentStreak': currentStreak,
        'bestStreak': bestStreak,
      };

  AntiTacticsStats copyWith({
    int? attempted,
    int? solved,
    int? noTacticCorrect,
    int? winningTacticCorrect,
    int? wrongAnswers,
    int? currentStreak,
    int? bestStreak,
  }) {
    return AntiTacticsStats(
      attempted: attempted ?? this.attempted,
      solved: solved ?? this.solved,
      noTacticCorrect: noTacticCorrect ?? this.noTacticCorrect,
      winningTacticCorrect: winningTacticCorrect ?? this.winningTacticCorrect,
      wrongAnswers: wrongAnswers ?? this.wrongAnswers,
      currentStreak: currentStreak ?? this.currentStreak,
      bestStreak: bestStreak ?? this.bestStreak,
    );
  }
}

class AntiTacticsStorage {
  static const _keySolvedIds = 'antiTactics_solvedIds';
  static const _keyWrongCounts = 'antiTactics_wrongCounts';
  static const _keyRecentIds = 'antiTactics_recentIds';
  static const _keyStats = 'antiTactics_stats';
  static const _keyLastTaskId = 'antiTactics_lastTaskId';

  Set<String> _solvedIds = {};
  Map<String, int> _wrongCounts = {};
  List<String> _recentIds = [];
  AntiTacticsStats _stats = const AntiTacticsStats();
  String? _lastTaskId;

  bool _initialized = false;

  AntiTacticsStorage._();
  static final AntiTacticsStorage instance = AntiTacticsStorage._();

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();

    _solvedIds = (prefs.getStringList(_keySolvedIds) ?? []).toSet();

    final wrongCountsStr = prefs.getString(_keyWrongCounts);
    if (wrongCountsStr != null) {
      try {
        final decoded = jsonDecode(wrongCountsStr) as Map<String, dynamic>;
        _wrongCounts = decoded.map((k, v) => MapEntry(k, v as int));
      } catch (_) {}
    }

    _recentIds = prefs.getStringList(_keyRecentIds) ?? [];

    final statsStr = prefs.getString(_keyStats);
    if (statsStr != null) {
      try {
        _stats = AntiTacticsStats.fromJson(jsonDecode(statsStr));
      } catch (_) {}
    }

    _lastTaskId = prefs.getString(_keyLastTaskId);
    _initialized = true;
  }

  Set<String> get solvedIds => _solvedIds;
  Map<String, int> get wrongCounts => _wrongCounts;
  List<String> get recentIds => _recentIds;
  AntiTacticsStats get stats => _stats;
  String? get lastTaskId => _lastTaskId;

  Future<void> saveLastTaskId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    _lastTaskId = id;
    await prefs.setString(_keyLastTaskId, id);
  }

  Future<void> recordResult({
    required String id,
    required bool solved,
    required bool isNoWinningTactic,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Update Recent
    _recentIds.remove(id);
    _recentIds.insert(0, id);
    if (_recentIds.length > 10) {
      _recentIds = _recentIds.sublist(0, 10);
    }
    await prefs.setStringList(_keyRecentIds, _recentIds);

    // Update task specific stats
    if (solved) {
      _solvedIds.add(id);
      await prefs.setStringList(_keySolvedIds, _solvedIds.toList());
      // Remove from wrong counts if solved
      if (_wrongCounts.containsKey(id)) {
        _wrongCounts.remove(id);
        await prefs.setString(_keyWrongCounts, jsonEncode(_wrongCounts));
      }
    } else {
      _wrongCounts[id] = (_wrongCounts[id] ?? 0) + 1;
      await prefs.setString(_keyWrongCounts, jsonEncode(_wrongCounts));
    }

    // Update global stats
    final streak = solved ? _stats.currentStreak + 1 : 0;
    _stats = _stats.copyWith(
      attempted: _stats.attempted + 1,
      solved: solved ? _stats.solved + 1 : _stats.solved,
      noTacticCorrect: (solved && isNoWinningTactic)
          ? _stats.noTacticCorrect + 1
          : _stats.noTacticCorrect,
      winningTacticCorrect: (solved && !isNoWinningTactic)
          ? _stats.winningTacticCorrect + 1
          : _stats.winningTacticCorrect,
      wrongAnswers: solved ? _stats.wrongAnswers : _stats.wrongAnswers + 1,
      currentStreak: streak,
      bestStreak: streak > _stats.bestStreak ? streak : _stats.bestStreak,
    );
    await prefs.setString(_keyStats, jsonEncode(_stats.toJson()));
  }
}
