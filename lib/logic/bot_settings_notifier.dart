import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Data Model
// ---------------------------------------------------------------------------
class BotSettings {
  final int elo;
  final String character;

  BotSettings({
    this.elo = 800,
    this.character = 'solid',
  });

  BotSettings copyWith({
    int? elo,
    String? character,
  }) {
    return BotSettings(
      elo: elo ?? this.elo,
      character: character ?? this.character,
    );
  }
}

// ---------------------------------------------------------------------------
// Repository Layer
// ---------------------------------------------------------------------------
class BotSettingsRepository {
  static const String _eloKey = 'bot_selected_elo';
  static const String _characterKey = 'bot_selected_character';

  Future<BotSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return BotSettings(
      elo: prefs.getInt(_eloKey) ?? 800,
      character: prefs.getString(_characterKey) ?? 'solid',
    );
  }

  Future<void> saveElo(int elo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_eloKey, elo);
  }

  Future<void> saveCharacter(String character) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_characterKey, character);
  }
}

final botSettingsRepositoryProvider = Provider<BotSettingsRepository>((ref) {
  return BotSettingsRepository();
});

// ---------------------------------------------------------------------------
// State Management (Riverpod Notifier)
// ---------------------------------------------------------------------------
class BotSettingsNotifier extends AsyncNotifier<BotSettings> {
  @override
  Future<BotSettings> build() async {
    return await ref.read(botSettingsRepositoryProvider).loadSettings();
  }

  /// Updates the elo value locally and persists it.
  Future<void> updateElo(int elo) async {
    final oldState = state.value ?? BotSettings();
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(botSettingsRepositoryProvider).saveElo(elo);
      return oldState.copyWith(elo: elo);
    });
  }

  /// Updates the character locally and persists it.
  Future<void> updateCharacter(String character) async {
    final oldState = state.value ?? BotSettings();
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(botSettingsRepositoryProvider).saveCharacter(character);
      return oldState.copyWith(character: character);
    });
  }
}

final botSettingsNotifierProvider = AsyncNotifierProvider<BotSettingsNotifier, BotSettings>(() {
  return BotSettingsNotifier();
});
