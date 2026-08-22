import 'package:flutter_test/flutter_test.dart';
import 'package:en_passant/logic/chess_board.dart';
import 'package:en_passant/logic/chess_piece.dart';
import 'package:en_passant/logic/puzzle/uci_move_converter.dart';

void main() {
  group('UCI Move Converter Tests', () {
    late ChessBoard board;

    setUp(() {
      board = ChessBoard();
    });

    test('Konvertiert normalen Zug (e2e4)', () {
      final move = uciToMove('e2e4', board);
      // e2 -> file 4, rank 6 (row 6) -> 6 * 8 + 4 = 52
      // e4 -> file 4, rank 4 (row 4) -> 4 * 8 + 4 = 36
      expect(move.from, 52);
      expect(move.to, 36);
      expect(move.promotionType, ChessPieceType.promotion);
    });

    test('Konvertiert Bauernumwandlung (e7e8q)', () {
      final move = uciToMove('e7e8q', board);
      // e7 -> file 4, rank 1 (row 1) -> 1 * 8 + 4 = 12
      // e8 -> file 4, rank 0 (row 0) -> 0 * 8 + 4 = 4
      expect(move.from, 12);
      expect(move.to, 4);
      expect(move.promotionType, ChessPieceType.queen);
    });

    test('Konvertiert Rochade Spezialfall (e1g1 = O-O Weiß)', () {
      final move = uciToMove('e1g1', board);
      expect(move.from, 60); // e1
      expect(move.to, 63); // h1 (intern wird bei Rochade auf den Turm gezogen)
    });

    test('Wirft Exception bei ungültiger Länge', () {
      expect(() => uciToMove('e2e', board), throwsFormatException);
      expect(() => uciToMove('e2e4qq', board), throwsFormatException);
    });

    test('Wirft Exception bei ungültigen Koordinaten', () {
      expect(() => uciToMove('i2i4', board), throwsFormatException);
      expect(() => uciToMove('e0e4', board), throwsFormatException);
      expect(() => uciToMove('e2e9', board), throwsFormatException);
    });

    test('Wirft Exception bei ungültigem Promotion-Typ', () {
      expect(() => uciToMove('e7e8x', board), throwsFormatException);
    });
  });
}
