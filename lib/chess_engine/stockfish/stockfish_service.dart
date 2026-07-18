import 'dart:async';
import 'package:stockfish/stockfish.dart';

class StockfishService {
  Stockfish? _engine;
  StreamSubscription<String>? _stdoutSubscription;
  Completer<String?>? _bestMoveCompleter;

  // Stream controller to expose raw engine responses (e.g. for logging or analysis graphs)
  final _responseController = StreamController<String>.broadcast();
  Stream<String> get responses => _responseController.stream;

  /// Initializes and boots the Stockfish engine.
  Future<void> initEngine() async {
    // Clean up any existing instances first
    await dispose();

    final engine = Stockfish();
    _engine = engine;

    // Listen to stdout from the engine isolate
    _stdoutSubscription = engine.stdout.listen((line) {
      _responseController.add(line);

      // Check if we are waiting for a bestmove command
      if (_bestMoveCompleter != null && !_bestMoveCompleter!.isCompleted) {
        if (line.startsWith('bestmove')) {
          // Format is: "bestmove e2e4 ponder e7e5" or "bestmove (none)"
          final parts = line.split(' ');
          if (parts.length > 1) {
            final bestMove = parts[1];
            if (bestMove == '(none)') {
              _bestMoveCompleter!.complete(null);
            } else {
              _bestMoveCompleter!.complete(bestMove);
            }
          } else {
            _bestMoveCompleter!.complete(null);
          }
          _bestMoveCompleter = null;
        }
      }
    });

    // Send standard UCI initialization commands
    engine.stdin = 'uci';
    engine.stdin = 'isready';
    engine.stdin = 'ucinewgame';
  }

  /// Sets the board position to a specific FEN.
  void setPosition(String fen) {
    final engine = _engine;
    if (engine == null) return;
    engine.stdin = 'position fen $fen';
  }

  /// Request the best move for the current position.
  /// [movetimeMs] is search time limit in milliseconds.
  /// [depth] is depth limit.
  Future<String?> getBestMove({int? movetimeMs, int? depth}) async {
    final engine = _engine;
    if (engine == null) return null;

    // If a request is already in progress, cancel it with null
    if (_bestMoveCompleter != null && !_bestMoveCompleter!.isCompleted) {
      _bestMoveCompleter!.complete(null);
    }

    _bestMoveCompleter = Completer<String?>();

    if (movetimeMs != null) {
      engine.stdin = 'go movetime $movetimeMs';
    } else if (depth != null) {
      engine.stdin = 'go depth $depth';
    } else {
      engine.stdin = 'go depth 10'; // Default depth limit
    }

    return _bestMoveCompleter!.future;
  }

  /// Disposes of the Stockfish instance and cancels subscriptions.
  Future<void> dispose() async {
    _stdoutSubscription?.cancel();
    _stdoutSubscription = null;

    if (_bestMoveCompleter != null && !_bestMoveCompleter!.isCompleted) {
      _bestMoveCompleter!.complete(null);
      _bestMoveCompleter = null;
    }

    final engine = _engine;
    if (engine != null) {
      engine.dispose();
      _engine = null;
    }
  }
}
