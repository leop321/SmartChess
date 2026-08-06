import '../logic/chess_piece.dart';
import '../logic/move_calculation/move_classes/move.dart';
import 'player.dart';

class CompletedGame {
  final DateTime date;
  final Player winner;
  final bool stalemate;
  final int aiDifficulty;
  final List<Move> moves;
  final int playerCount;
  final Player playerSide; // Which side the user played (in 1-player mode)

  CompletedGame({
    required this.date,
    required this.winner,
    required this.stalemate,
    required this.aiDifficulty,
    required this.moves,
    required this.playerCount,
    required this.playerSide,
  });

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'winner': winner.index,
      'stalemate': stalemate,
      'aiDifficulty': aiDifficulty,
      'moves': moves.map((m) {
        if (m.promotionType != ChessPieceType.promotion) {
          return '${m.from}-${m.to}-${_promotionChar(m.promotionType)}';
        }
        return '${m.from}-${m.to}';
      }).toList(),
      'playerCount': playerCount,
      'playerSide': playerSide.index,
    };
  }

  factory CompletedGame.fromJson(Map<String, dynamic> json) {
    return CompletedGame(
      date: DateTime.parse(json['date']),
      winner: Player.values[json['winner'] as int],
      stalemate: json['stalemate'] as bool,
      aiDifficulty: json['aiDifficulty'] as int,
      moves: (json['moves'] as List<dynamic>).map((m) {
        final parts = (m as String).split('-');
        final from = int.parse(parts[0]);
        final to = int.parse(parts[1]);
        ChessPieceType? promotionType;
        if (parts.length == 3) {
          promotionType = _parsePromotionChar(parts[2]);
        }
        return Move(from, to,
            promotionType: promotionType ?? ChessPieceType.promotion);
      }).toList(),
      playerCount: json['playerCount'] as int? ?? 1,
      playerSide: Player.values[json['playerSide'] as int? ?? 0],
    );
  }

  static String _promotionChar(ChessPieceType type) {
    switch (type) {
      case ChessPieceType.queen:
        return 'q';
      case ChessPieceType.rook:
        return 'r';
      case ChessPieceType.knight:
        return 'n';
      case ChessPieceType.bishop:
        return 'b';
      case ChessPieceType.pawn:
        return 'p';
      case ChessPieceType.king:
        return 'k';
      case ChessPieceType.promotion:
        return '';
    }
  }

  static ChessPieceType? _parsePromotionChar(String char) {
    switch (char) {
      case 'q':
        return ChessPieceType.queen;
      case 'r':
        return ChessPieceType.rook;
      case 'n':
        return ChessPieceType.knight;
      case 'b':
        return ChessPieceType.bishop;
      default:
        return null;
    }
  }
}
