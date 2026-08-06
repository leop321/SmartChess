import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../model/player.dart';

class PeekingState {
  final int
      peekFrequency; // Move frequency for awarding peeks (default: every 5 moves)
  final int player1Tokens;
  final int player2Tokens;
  final bool showBoardOverride; // Temp flag to render pieces during peek
  final int player1Moves;
  final int player2Moves;

  PeekingState({
    required this.peekFrequency,
    required this.player1Tokens,
    required this.player2Tokens,
    required this.showBoardOverride,
    required this.player1Moves,
    required this.player2Moves,
  });

  PeekingState copyWith({
    int? peekFrequency,
    int? player1Tokens,
    int? player2Tokens,
    bool? showBoardOverride,
    int? player1Moves,
    int? player2Moves,
  }) {
    return PeekingState(
      peekFrequency: peekFrequency ?? this.peekFrequency,
      player1Tokens: player1Tokens ?? this.player1Tokens,
      player2Tokens: player2Tokens ?? this.player2Tokens,
      showBoardOverride: showBoardOverride ?? this.showBoardOverride,
      player1Moves: player1Moves ?? this.player1Moves,
      player2Moves: player2Moves ?? this.player2Moves,
    );
  }
}

class PeekingNotifier extends Notifier<PeekingState> {
  @override
  PeekingState build() {
    return PeekingState(
      peekFrequency: 5,
      player1Tokens: 0,
      player2Tokens: 0,
      showBoardOverride: false,
      player1Moves: 0,
      player2Moves: 0,
    );
  }

  void configureFrequency(int frequency) {
    state = state.copyWith(peekFrequency: frequency);
  }

  /// Increments move count and awards a peek token if frequency is met
  void handleMoveCompleted(Player player) {
    if (player == Player.player1) {
      final newMoves = state.player1Moves + 1;
      if (newMoves >= state.peekFrequency) {
        state = state.copyWith(
          player1Tokens: state.player1Tokens + 1,
          player1Moves: 0,
        );
      } else {
        state = state.copyWith(player1Moves: newMoves);
      }
    } else {
      final newMoves = state.player2Moves + 1;
      if (newMoves >= state.peekFrequency) {
        state = state.copyWith(
          player2Tokens: state.player2Tokens + 1,
          player2Moves: 0,
        );
      } else {
        state = state.copyWith(player2Moves: newMoves);
      }
    }
  }

  /// Consumes one token to temporarily reveal the board
  bool consumeTokenForPeek(Player player) {
    if (player == Player.player1) {
      if (state.player1Tokens > 0) {
        state = state.copyWith(
          player1Tokens: state.player1Tokens - 1,
          showBoardOverride: true,
        );
        return true;
      }
    } else {
      if (state.player2Tokens > 0) {
        state = state.copyWith(
          player2Tokens: state.player2Tokens - 1,
          showBoardOverride: true,
        );
        return true;
      }
    }
    return false;
  }

  /// Consumes one token in Snapshot mode to update the board without a timer reveal
  bool consumeTokenForUpdate(Player player) {
    if (player == Player.player1) {
      if (state.player1Tokens > 0) {
        state = state.copyWith(
          player1Tokens: state.player1Tokens - 1,
        );
        return true;
      }
    } else {
      if (state.player2Tokens > 0) {
        state = state.copyWith(
          player2Tokens: state.player2Tokens - 1,
        );
        return true;
      }
    }
    return false;
  }

  /// Manually awards an extra peek token
  void awardToken(Player player) {
    if (player == Player.player1) {
      state = state.copyWith(player1Tokens: state.player1Tokens + 1);
    } else {
      state = state.copyWith(player2Tokens: state.player2Tokens + 1);
    }
  }

  /// Triggers a temporary reveal on game resumption without consuming a token.
  void triggerResumePeek() {
    state = state.copyWith(showBoardOverride: true);
  }

  /// Resets only the temporary board reveal override
  void resetPeekOverride() {
    state = state.copyWith(showBoardOverride: false);
  }

  /// Full reset of token and move counters for a new game
  void reset() {
    state = PeekingState(
      peekFrequency: state.peekFrequency,
      player1Tokens: 0,
      player2Tokens: 0,
      showBoardOverride: false,
      player1Moves: 0,
      player2Moves: 0,
    );
  }
}

final peekingProvider = NotifierProvider<PeekingNotifier, PeekingState>(() {
  return PeekingNotifier();
});
