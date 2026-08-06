import 'dart:async';

import 'package:flutter/foundation.dart';

import 'chess_piece.dart';
import 'game_controller.dart';
import 'move_calculation/move_classes/move.dart';
import 'remote_ai_service.dart';

class StockfishService {
  static final StockfishService instance = StockfishService._();
  factory StockfishService() => instance;
  StockfishService._();

  void init() {
    debugPrint('[StockfishService] Local Stockfish engine is disabled on web.');
  }

  Future<Move> getBestMove(String movesString, int difficulty) async {
    debugPrint(
        '[StockfishService] getBestMove called on web. Local engine is not supported.');
    return Move(0, 0);
  }

  static String msoToUCI(dynamic mso) {
    if (mso.castled == true) {
      int kingTile = mso.move.from;
      int otherTile = mso.move.to;
      if (mso.movedPiece?.type == ChessPieceType.rook) {
        kingTile = mso.move.to;
        otherTile = mso.move.from;
      }
      if (kingTile == 60) {
        if (otherTile == 63) return 'e1g1';
        if (otherTile == 56) return 'e1c1';
      } else if (kingTile == 4) {
        if (otherTile == 7) return 'e8g8';
        if (otherTile == 0) return 'e8c8';
      }
    }

    Move move = mso.move;
    int from = move.from;
    int to = move.to;

    int fromFile = from % 8;
    int fromRank = 8 - (from ~/ 8);
    int toFile = to % 8;
    int toRank = 8 - (to ~/ 8);

    String fromStr = '${String.fromCharCode(97 + fromFile)}$fromRank';
    String toStr = '${String.fromCharCode(97 + toFile)}$toRank';

    String promo = '';
    if (mso.promotion && mso.promotionType != null) {
      switch (mso.promotionType) {
        case ChessPieceType.queen:
          promo = 'q';
          break;
        case ChessPieceType.rook:
          promo = 'r';
          break;
        case ChessPieceType.bishop:
          promo = 'b';
          break;
        case ChessPieceType.knight:
          promo = 'n';
          break;
        default:
          break;
      }
    }
    return '$fromStr$toStr$promo';
  }

  /// Evaluates a FEN position for the analysis page.
  /// On Web, this only calls the remote AI service.
  Future<Map<String, dynamic>> evaluateFenForAnalysis(
    String fen, {
    int depth = 14,
    int timeoutMs = 4000,
  }) async {
    try {
      final remoteAi = providerContainer.read(remoteAiServiceProvider);
      final remoteResult = await remoteAi.analyzeFen(fen, depth: depth);
      return {
        'best_eval': remoteResult.bestEval,
        'is_mate': remoteResult.isMate,
        'suggestions': remoteResult.suggestions,
        'alternatives': remoteResult.alternatives,
      };
    } catch (e) {
      debugPrint('[StockfishService] Remote analysis failed on Web: $e');
    }

    return {
      'best_eval': 0.0,
      'is_mate': false,
      'suggestions': <String>[],
      'alternatives': <double>[]
    };
  }

  void dispose() {
    debugPrint('[StockfishService] Disposing web stub.');
  }
}
