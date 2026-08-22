import 'dart:async';

import 'package:en_passant/logic/chess_board.dart';
import 'package:en_passant/logic/move_calculation/move_classes/move.dart';
import 'package:en_passant/logic/puzzle/fake_puzzle_repository.dart';
import 'package:en_passant/logic/puzzle/puzzle_session_state.dart';
import 'package:en_passant/model/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Hilfsfunktion: wartet bis Status einen bestimmten Wert hat ──

Future<void> waitForStatus(
  PuzzleSessionState state,
  PuzzleStatus target, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  if (state.status == target) return;
  final completer = Completer<void>();
  void listener() {
    if (state.status == target && !completer.isCompleted) {
      completer.complete();
    }
  }

  state.addListener(listener);
  try {
    await completer.future.timeout(timeout);
  } finally {
    state.removeListener(listener);
  }
}

/// Wartet bis currentPuzzle gesetzt und Status waitingForPlayerMove ist.
Future<Puzzle> waitForPuzzleLoaded(PuzzleSessionState state) async {
  await waitForStatus(state, PuzzleStatus.waitingForPlayerMove);
  return state.currentPuzzle!;
}

/// Spielt alle Spieler-Züge eines Puzzles korrekt durch bis solved.
Future<void> playThroughPuzzle(
    PuzzleSessionState state, Puzzle puzzle) async {
  for (int i = 1; i < puzzle.solutionMoves.length; i += 2) {
    await waitForStatus(state, PuzzleStatus.waitingForPlayerMove);

    final uci = puzzle.solutionMoves[i];
    final move = _parseUci(uci);
    state.handleTap(move.from);
    state.handleTap(move.to);

    await waitForStatus(state, PuzzleStatus.correct);
  }
  await waitForStatus(state, PuzzleStatus.solved);
}

/// Einfache UCI-Parse-Funktion für Tests (ohne board-Kontext).
Move _parseUci(String uci) {
  if (uci == 'e1g1') return Move(60, 63);
  if (uci == 'e1c1') return Move(60, 56);
  if (uci == 'e8g8') return Move(4, 7);
  if (uci == 'e8c8') return Move(4, 0);
  final fromFile = uci.codeUnitAt(0) - 97;
  final fromRank = 8 - int.parse(uci[1]);
  final toFile = uci.codeUnitAt(2) - 97;
  final toRank = 8 - int.parse(uci[3]);
  return Move(fromRank * 8 + fromFile, toRank * 8 + toFile);
}

/// Serialisiert den Board-Zustand als String (FEN-Ersatz für Tests).
String boardSnapshot(ChessBoard board) {
  final sb = StringBuffer();
  for (int i = 0; i < 64; i++) {
    final piece = board.tiles[i];
    if (piece == null) {
      sb.write('.');
    } else {
      sb.write('${piece.player.name[0]}${piece.type.name[0]}');
    }
  }
  return sb.toString();
}

/// Findet einen legalen Zug der NICHT der erwartete Lösungszug ist.
Move? findWrongMove(PuzzleSessionState state, String expectedUci) {
  final allPieces = [
    ...state.board.player1Pieces,
    ...state.board.player2Pieces,
  ];
  for (final piece in allPieces) {
    final moves = state.board.movesForPiece(piece, legal: true);
    for (final toTile in moves) {
      final move = Move(piece.tile, toTile);
      final uci = _moveToUci(move);
      if (uci != expectedUci) return move;
    }
  }
  return null;
}

String _moveToUci(Move move) {
  if (move.from == 60 && move.to == 63) return 'e1g1';
  if (move.from == 60 && move.to == 56) return 'e1c1';
  if (move.from == 4 && move.to == 7) return 'e8g8';
  if (move.from == 4 && move.to == 0) return 'e8c8';
  final fromRank = move.from ~/ 8;
  final fromFile = move.from % 8;
  final toRank = move.to ~/ 8;
  final toFile = move.to % 8;
  return String.fromCharCode(fromFile + 97) +
      (8 - fromRank).toString() +
      String.fromCharCode(toFile + 97) +
      (8 - toRank).toString();
}

// ─────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────

void main() {
  late FakePuzzleRepository repo;
  late PuzzleSessionState state;

  setUp(() {
    repo = FakePuzzleRepository();
    state = PuzzleSessionState();
  });

  tearDown(() {
    state.dispose();
  });

  test('Initialer Status ist loading', () {
    expect(state.status, PuzzleStatus.loading);
    expect(state.currentPuzzle, isNull);
  });

  test('loadNextPuzzle wechselt zu showingOpponentMove dann waitingForPlayerMove',
      () async {
    state.loadNextPuzzle(repo);
    await waitForStatus(state, PuzzleStatus.showingOpponentMove);
    expect(state.currentPuzzle, isNotNull);
    await waitForStatus(state, PuzzleStatus.waitingForPlayerMove);
    // Gegnerzug wurde auf dem Board ausgeführt
    expect(state.board.moveStack, isNotEmpty);
    expect(state.latestMove, isNotNull);
  });

  test('Falscher Zug → status incorrect, Board-Zustand identisch nach Undo',
      () async {
    state.loadNextPuzzle(repo);
    final puzzle = await waitForPuzzleLoaded(state);

    // Snapshot vor dem Fehlzug
    final snapshotBefore = boardSnapshot(state.board);

    final expectedUci = puzzle.solutionMoves[1];
    final wrongMove = findWrongMove(state, expectedUci);
    if (wrongMove == null) {
      // Kein anderer legaler Zug vorhanden – Skip
      return;
    }

    state.handleTap(wrongMove.from);
    state.handleTap(wrongMove.to);

    await waitForStatus(state, PuzzleStatus.incorrect);
    expect(state.status, PuzzleStatus.incorrect);

    // Nach Undo-Delay (700ms) → waitingForPlayerMove
    await waitForStatus(state, PuzzleStatus.waitingForPlayerMove);
    expect(boardSnapshot(state.board), equals(snapshotBefore),
        reason: 'Board-Zustand muss nach Fehlzug-Undo identisch sein');
  });

  test('Fake-Puzzle 1: korrekter Vollablauf (laden → Gegnerzug → Player → solved)',
      () async {
    state.loadNextPuzzle(repo);
    final puzzle = await waitForPuzzleLoaded(state);
    await playThroughPuzzle(state, puzzle);
    expect(state.status, PuzzleStatus.solved);
  });

  test('Fake-Puzzle 2: korrekter Vollablauf', () async {
    // Erstes Puzzle überspringen (Repo rotiert)
    await _skipPuzzle(repo);
    // Zweites Puzzle laden
    state.loadNextPuzzle(repo);
    final puzzle = await waitForPuzzleLoaded(state);
    await playThroughPuzzle(state, puzzle);
    expect(state.status, PuzzleStatus.solved);
  });

  test('Fake-Puzzle 3: korrekter Vollablauf', () async {
    // Erste zwei Puzzles überspringen
    await _skipPuzzle(repo);
    await _skipPuzzle(repo);
    // Drittes Puzzle laden
    state.loadNextPuzzle(repo);
    final puzzle = await waitForPuzzleLoaded(state);
    await playThroughPuzzle(state, puzzle);
    expect(state.status, PuzzleStatus.solved);
  });

  test('Nach solved: loadNextPuzzle startet neues Puzzle', () async {
    state.loadNextPuzzle(repo);
    final puzzle = await waitForPuzzleLoaded(state);
    await playThroughPuzzle(state, puzzle);
    expect(state.status, PuzzleStatus.solved);

    // Neues Puzzle
    state.loadNextPuzzle(repo);
    await waitForStatus(state, PuzzleStatus.waitingForPlayerMove);
    expect(state.status, PuzzleStatus.waitingForPlayerMove);
    // Ist ein anderes (oder rotiertes) Puzzle
    expect(state.currentPuzzle, isNotNull);
  });
}

/// Hilfsfunktion: Lädt ein Puzzle und verwirft es.
Future<void> _skipPuzzle(FakePuzzleRepository repo) async {
  final skipState = PuzzleSessionState();
  skipState.loadNextPuzzle(repo);
  await waitForStatus(skipState, PuzzleStatus.waitingForPlayerMove);
  skipState.dispose();
}
