import 'puzzle.dart';

const List<ChessPuzzle> offlinePuzzles = [
  ChessPuzzle(
    id: 'back_rank_1',
    startingFen: '6k1/5ppp/8/8/8/8/3R4/6K1 w - - 0 1',
    solutionMoves: ['d2d8'],
    theme: 'Mate in 1',
    description: 'Find the checkmate on the back rank.',
  ),
  ChessPuzzle(
    id: 'scholars_mate',
    startingFen: 'r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5Q2/PPPP1PPP/RNB1K1NR w KQkq - 4 4',
    solutionMoves: ['f3f7'],
    theme: 'Mate in 1',
    description: 'Expose the weak f7 square.',
  ),
  ChessPuzzle(
    id: 'knight_fork_1',
    startingFen: 'r3k3/8/8/3N4/8/8/8/6K1 w q - 0 1',
    solutionMoves: ['d5c7', 'e8d7', 'c7a8'],
    theme: 'Fork',
    description: 'Find the move that forks the King and the Rook, and then capture the Rook.',
  ),
];
