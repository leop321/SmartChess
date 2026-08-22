import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ChessMode {
  normal,
  blind,
  snapshot,
}

class GameModeNotifier extends Notifier<ChessMode> {
  @override
  ChessMode build() => ChessMode.normal;

  void setMode(ChessMode mode) {
    state = mode;
  }
}

final gameModeProvider = NotifierProvider<GameModeNotifier, ChessMode>(() {
  return GameModeNotifier();
});
