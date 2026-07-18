class MoveParser {
  /// Parses a chess move in Standard Algebraic Notation (SAN)
  /// and returns a list of phonetic tokens (e.g. ['knight', 'takes', 'd', '4']).
  ///
  /// The tokens returned are lowercase and correspond to pre-recorded assets:
  /// - Pieces: 'king', 'queen', 'rook', 'bishop', 'knight', 'pawn'
  /// - Letters: 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'
  /// - Numbers: '1', '2', '3', '4', '5', '6', '7', '8'
  /// - Actions: 'takes', 'castle', 'long_castle'
  static List<String> parseSan(String san) {
    // 1. Castling
    if (san == 'O-O' || san == '0-0') {
      return ['castle'];
    }
    if (san == 'O-O-O' || san == '0-0-0') {
      return ['long_castle'];
    }

    // Clean check (+), checkmate (#), and annotations (?, !, etc.)
    final cleanSan = san.replaceAll(RegExp(r'[+#?!]'), '');

    final List<String> tokens = [];

    // Parse piece name
    String remaining = cleanSan;
    String? piece;
    if (cleanSan.startsWith('K')) {
      piece = 'king';
      remaining = cleanSan.substring(1);
    } else if (cleanSan.startsWith('Q')) {
      piece = 'queen';
      remaining = cleanSan.substring(1);
    } else if (cleanSan.startsWith('R')) {
      piece = 'rook';
      remaining = cleanSan.substring(1);
    } else if (cleanSan.startsWith('B')) {
      piece = 'bishop';
      remaining = cleanSan.substring(1);
    } else if (cleanSan.startsWith('N')) {
      piece = 'knight';
      remaining = cleanSan.substring(1);
    }

    // Check if it's a capture
    final isCapture = remaining.contains('x');

    if (piece != null) {
      tokens.add(piece);
    }

    // If it's a pawn capture (e.g. exd5), the first char is the moving pawn's file
    if (piece == null && isCapture) {
      final parts = remaining.split('x');
      if (parts.isNotEmpty) {
        final pawnFile = parts[0];
        if (pawnFile.length == 1 && RegExp(r'[a-h]').hasMatch(pawnFile)) {
          tokens.add(pawnFile.toLowerCase());
        }
      }
    }

    if (isCapture) {
      tokens.add('takes');
      // Focus on the part after 'x'
      remaining = remaining.substring(remaining.indexOf('x') + 1);
    }

    // Find destination square (file and rank, e.g. "d4")
    // In case of disambiguated moves (like Nbd2 or R1e2), the destination square
    // is always at the end. We match the last file-rank combination in the string.
    final match = RegExp(r'([a-h])([1-8])').firstMatch(remaining);
    if (match != null) {
      final file = match.group(1)!;
      final rank = match.group(2)!;
      tokens.add(file.toLowerCase());
      tokens.add(rank);
    }

    // Handle pawn promotion (e.g. e8=Q)
    if (cleanSan.contains('=')) {
      final parts = cleanSan.split('=');
      if (parts.length > 1) {
        final promoPart = parts[1];
        if (promoPart.startsWith('Q')) {
          tokens.add('queen');
        } else if (promoPart.startsWith('R')) {
          tokens.add('rook');
        } else if (promoPart.startsWith('B')) {
          tokens.add('bishop');
        } else if (promoPart.startsWith('N')) {
          tokens.add('knight');
        }
      }
    }

    return tokens;
  }
}
