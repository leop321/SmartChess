import 'package:flame/game.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../logic/chess_game.dart';
import '../logic/game_mode_notifier.dart';
import '../logic/tactics_controller_2.dart';
import '../model/app_model.dart';

class TacticsView2 extends StatefulWidget {
  const TacticsView2({Key? key}) : super(key: key);

  @override
  State<TacticsView2> createState() => _TacticsView2State();
}

class _TacticsView2State extends State<TacticsView2> {
  late TacticsController2 _controller;
  late AppModel _puzzleAppModel;
  ChessGame? _chessGame;

  @override
  void initState() {
    super.initState();
    final globalAppModel = context.read<AppModel>();

    _puzzleAppModel = AppModel();
    _puzzleAppModel.prefs.themeName = globalAppModel.prefs.themeName;
    _puzzleAppModel.prefs.pieceTheme = globalAppModel.prefs.pieceTheme;
    _puzzleAppModel.prefs.soundEnabled = globalAppModel.prefs.soundEnabled;
    _puzzleAppModel.prefs.hapticEnabled = globalAppModel.prefs.hapticEnabled;
    _puzzleAppModel.gameMode = ChessMode.tactics2;
    _puzzleAppModel.playerCount = 2;

    _controller = TacticsController2(globalAppModel, _puzzleAppModel);
    _chessGame = ChessGame(_controller.puzzleGameController, _puzzleAppModel);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fetchDailyPuzzle();
    });
  }

  @override
  void dispose() {
    _controller.disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TacticsController2>.value(
      value: _controller,
      child: Consumer2<AppModel, TacticsController2>(
        builder: (context, appModel, controller, child) {
          final theme = appModel.theme;
          return Scaffold(
            backgroundColor: theme.background?.colors.first ?? Colors.black,
            body: SafeArea(
              child: Column(
                children: [
                  _buildHeader(theme, controller),
                  _buildPuzzleInfo(theme, controller),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildBoard(controller),
                    ),
                  ),
                  _buildStatus(controller),
                  _buildBottomGraph(appModel),
                  if (controller.status == PuzzleStatus.solved ||
                      controller.status == PuzzleStatus.error)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: CupertinoButton.filled(
                        child: const Text('Nächstes Puzzle'),
                        onPressed: () => controller.fetchRandomPuzzle(),
                      ),
                    )
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(dynamic theme, TacticsController2 controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            child: Icon(Icons.arrow_back_ios, color: theme.lightTile),
          ),
          Text(
            'Taktikaufgaben 2.0',
            style: TextStyle(
                color: theme.lightTile,
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 32),
        ],
      ),
    );
  }

  Widget _buildPuzzleInfo(dynamic theme, TacticsController2 controller) {
    if (controller.currentPuzzle == null) return const SizedBox(height: 50);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(
        'Rating: ${controller.currentPuzzle!.rating} ELO',
        style: TextStyle(
            color: theme.lightTile, fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildBoard(TacticsController2 controller) {
    if (controller.status == PuzzleStatus.loading) {
      return const Center(child: CupertinoActivityIndicator(radius: 20));
    }
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: GameWidget(game: _chessGame!),
      ),
    );
  }

  Widget _buildStatus(TacticsController2 controller) {
    String msg = '';
    Color c = Colors.white;
    switch (controller.status) {
      case PuzzleStatus.correct:
        msg = 'Richtig!';
        c = Colors.green;
        break;
      case PuzzleStatus.wrong:
        msg = 'Falsch! Versuche es noch einmal.';
        c = Colors.red;
        break;
      case PuzzleStatus.solved:
        msg = 'Puzzle Gelöst!';
        c = Colors.greenAccent;
        break;
      case PuzzleStatus.error:
        msg = controller.errorMessage;
        c = Colors.red;
        break;
      default:
        msg = 'Finde den besten Zug';
        c = Colors.white70;
        break;
    }
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(msg,
          style:
              TextStyle(color: c, fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildBottomGraph(AppModel appModel) {
    if (appModel.puzzleStreak.isEmpty) return const SizedBox(height: 100);

    List<FlSpot> spots = [];
    for (int i = 0; i < appModel.puzzleStreak.length; i++) {
      spots.add(FlSpot(i.toDouble(), appModel.puzzleStreak[i].elo));
    }

    return Container(
      height: 120,
      padding: const EdgeInsets.all(16),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: false),
          titlesData: FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.blueAccent,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(show: true),
              belowBarData: BarAreaData(
                  show: true, color: Colors.blueAccent.withValues(alpha: 0.3)),
            ),
          ],
        ),
      ),
    );
  }
}
