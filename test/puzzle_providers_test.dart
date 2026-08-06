import 'package:en_passant/logic/puzzle_providers/asset_anti_tactics_provider.dart';
import 'package:en_passant/logic/puzzle_providers/lichess_anti_tactics_v2_provider.dart';
import 'package:en_passant/logic/puzzle_providers/rating_aware_classic_provider.dart';
import 'package:en_passant/logic/puzzle_providers/unified_tactics_session_manager.dart';
import 'package:en_passant/model/tactics_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('RatingAwareClassicProvider fetchNextTask', () async {
    final classic = RatingAwareClassicProvider();
    try {
      final task = await classic.fetchNextTask();
      print(
          'Classic task ID: ${task.id}, FEN: ${task.fen}, Moves: ${task.expectedMoves}');
    } catch (e, st) {
      print('Classic ERROR: $e\n$st');
      rethrow;
    }
  });

  test('AssetAntiTacticsProvider fetchNextTask', () async {
    final assetAnti =
        AssetAntiTacticsProvider(targetMode: TacticsMode.antiTactics);
    try {
      final task = await assetAnti.fetchNextTask();
      print(
          'AssetAnti task ID: ${task.id}, FEN: ${task.fen}, Moves: ${task.expectedMoves}');
    } catch (e, st) {
      print('AssetAnti ERROR: $e\n$st');
      rethrow;
    }
  });

  test('LichessAntiTacticsV2Provider fetchNextTask', () async {
    final v2 = LichessAntiTacticsV2Provider();
    try {
      final task = await v2.fetchNextTask();
      print(
          'V2 task ID: ${task.id}, FEN: ${task.fen}, Moves: ${task.expectedMoves}');
    } catch (e, st) {
      print('V2 ERROR: $e\n$st');
      rethrow;
    }
  });

  test('UnifiedTacticsSessionManager fetchNextTask', () async {
    final unified = UnifiedTacticsSessionManager();
    try {
      final task = await unified.fetchNextTask();
      print(
          'Unified task ID: ${task.id}, FEN: ${task.fen}, Mode: ${task.mode}, Moves: ${task.expectedMoves}');
    } catch (e, st) {
      print('Unified ERROR: $e\n$st');
      rethrow;
    }
  });
}
