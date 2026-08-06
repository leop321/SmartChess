import 'package:chess/chess.dart' as ch;

void main() {
  final board =
      ch.Chess.fromFEN('r6k/pp2r2p/4Rp1Q/3p4/8/1N1P2R1/PqP2bPP/7K b - - 0 24');
  board.move({'from': 'f2', 'to': 'g3'});
  print(board.fen);
}
