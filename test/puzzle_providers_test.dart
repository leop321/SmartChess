import 'package:en_passant/logic/puzzle_providers/asset_anti_tactics_provider.dart';
import 'package:en_passant/logic/puzzle_providers/lichess_anti_tactics_v2_provider.dart';
import 'package:en_passant/logic/puzzle_providers/rating_aware_classic_provider.dart';
import 'package:en_passant/logic/puzzle_providers/unified_tactics_session_manager.dart';
import 'package:en_passant/model/app_model.dart';
import 'package:en_passant/model/lichess_puzzle.dart';
import 'package:en_passant/model/player.dart';
import 'package:en_passant/model/tactics_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('RatingAwareClassicProvider serves diverse non-repeating puzzles',
      () async {
    final classic = RatingAwareClassicProvider();
    final Set<String> seenIds = {};

    for (int i = 0; i < 5; i++) {
      final task = await classic.fetchNextTask();
      expect(seenIds.contains(task.id), isFalse,
          reason: 'Puzzle ${task.id} was served repeatedly!');
      seenIds.add(task.id);
      expect(task.expectedMoves.isNotEmpty, isTrue);
      expect(task.fen.isNotEmpty, isTrue);
    }
  });

  test('LichessPuzzle.fromJson parses and replays complex annotated PGN', () {
    final rawJson = {
      'game': {
        'id': 'testGame123',
        'pgn': r'[Event "Live Chess"]'
            '\n'
            r'[Site "Chess.com"]'
            '\n'
            r'1. e4 { [%clk 0:03:00] } 1... e5 { [%clk 0:03:00] } 2. Nf3 $1 2... Nc6 3. Bc4 Bc5 4. c3 Nf6 5. d4 exd4 6. cxd4 Bb4+ 7. Bd2 Bxd2+ 8. Nbxd2 d5 9. exd5 Nxd5 10. Qb3 Nce7 11. O-O O-O',
      },
      'puzzle': {
        'id': 'annotatedPgnPuzzle',
        'initialPly': 20,
        'solution': ['e8g8', 'f1e1'],
        'rating': 1500,
        'themes': ['middlegame', 'short'],
      }
    };

    final puzzle = LichessPuzzle.fromJson(rawJson);
    expect(puzzle.isValidPuzzle, isTrue);
    expect(puzzle.fen.isNotEmpty, isTrue);
    expect(puzzle.lastMove, isNotNull);
  });

  test('Tactics board inversion remains constant on turn switch', () {
    final appModel = AppModel();
    appModel.isTacticsMode = true;
    appModel.playerSide = Player.player2; // Black to move

    appModel.turn = Player.player2;
    expect(appModel.isBoardInverted, isTrue);

    // After black plays, turn changes to white, but board orientation should NOT flip
    appModel.turn = Player.player1;
    expect(appModel.isBoardInverted, isTrue);

    // Same for White
    appModel.playerSide = Player.player1;
    appModel.turn = Player.player1;
    expect(appModel.isBoardInverted, isFalse);
    appModel.turn = Player.player2;
    expect(appModel.isBoardInverted, isFalse);
  });

  test('AssetAntiTacticsProvider fetchNextTask', () async {
    final assetAnti =
        AssetAntiTacticsProvider(targetMode: TacticsMode.antiTactics);
    final task = await assetAnti.fetchNextTask();
    expect(task.id.isNotEmpty, isTrue);
    expect(task.fen.isNotEmpty, isTrue);
  });

  test('LichessAntiTacticsV2Provider fetchNextTask', () async {
    final v2 = LichessAntiTacticsV2Provider();
    final task = await v2.fetchNextTask();
    expect(task.id.isNotEmpty, isTrue);
    expect(task.fen.isNotEmpty, isTrue);
  });

  test('UnifiedTacticsSessionManager fetchNextTask', () async {
    final unified = UnifiedTacticsSessionManager();
    final task = await unified.fetchNextTask();
    expect(task.id.isNotEmpty, isTrue);
    expect(task.fen.isNotEmpty, isTrue);
  });
}
