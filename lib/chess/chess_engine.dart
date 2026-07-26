// Motor de reglas de ajedrez, independiente de la UI.
//
// El tablero se representa como una lista de 64 casillas (índice 0..63),
// fila = index ~/ 8, columna = index % 8. La fila 0 es la fila de piezas
// negras (arriba) y la fila 7 la de piezas blancas (abajo), tal como se
// dibuja en pantalla.

enum PieceColor { white, black }

enum PieceType { pawn, knight, bishop, rook, queen, king }

enum GameStatus { playing, check, checkmate, stalemate }

class ChessPiece {
  final PieceType type;
  final PieceColor color;

  const ChessPiece(this.type, this.color);

  /// Notación usada por la UI (Torre, Caballo, Alfil, Dama, Rey, Peón).
  /// Mayúscula = blancas, minúscula = negras.
  String get symbol {
    const letters = {
      PieceType.pawn: 'p',
      PieceType.knight: 'c',
      PieceType.bishop: 'a',
      PieceType.rook: 't',
      PieceType.queen: 'd',
      PieceType.king: 'r',
    };
    final letter = letters[type]!;
    return color == PieceColor.white ? letter.toUpperCase() : letter;
  }
}

class ChessMove {
  final int from;
  final int to;
  final PieceType? promotion;

  const ChessMove(this.from, this.to, {this.promotion});

  @override
  bool operator ==(Object other) =>
      other is ChessMove &&
      other.from == from &&
      other.to == to &&
      other.promotion == promotion;

  @override
  int get hashCode => Object.hash(from, to, promotion);
}

class _BoardSnapshot {
  final List<ChessPiece?> board;
  final int? enPassantTarget;
  final bool whiteKingMoved;
  final bool blackKingMoved;
  final bool whiteRookAMoved;
  final bool whiteRookHMoved;
  final bool blackRookAMoved;
  final bool blackRookHMoved;

  _BoardSnapshot({
    required this.board,
    required this.enPassantTarget,
    required this.whiteKingMoved,
    required this.blackKingMoved,
    required this.whiteRookAMoved,
    required this.whiteRookHMoved,
    required this.blackRookAMoved,
    required this.blackRookHMoved,
  });
}

class ChessEngine {
  late List<ChessPiece?> board;
  PieceColor turn = PieceColor.white;

  bool whiteKingMoved = false;
  bool blackKingMoved = false;
  bool whiteRookAMoved = false; // torre de la columna a (enroque largo)
  bool whiteRookHMoved = false; // torre de la columna h (enroque corto)
  bool blackRookAMoved = false;
  bool blackRookHMoved = false;

  /// Casilla vacía "detrás" de un peón que acaba de avanzar dos casillas,
  /// capturable al paso en el siguiente movimiento.
  int? enPassantTarget;

  final List<ChessPiece> capturedByWhite = [];
  final List<ChessPiece> capturedByBlack = [];

  ChessEngine() {
    _resetBoard();
  }

  void reset() => _resetBoard();

  void _resetBoard() {
    board = List<ChessPiece?>.filled(64, null);
    const backRank = [
      PieceType.rook,
      PieceType.knight,
      PieceType.bishop,
      PieceType.queen,
      PieceType.king,
      PieceType.bishop,
      PieceType.knight,
      PieceType.rook,
    ];
    for (int col = 0; col < 8; col++) {
      board[col] = ChessPiece(backRank[col], PieceColor.black);
      board[8 + col] = const ChessPiece(PieceType.pawn, PieceColor.black);
      board[48 + col] = const ChessPiece(PieceType.pawn, PieceColor.white);
      board[56 + col] = ChessPiece(backRank[col], PieceColor.white);
    }
    turn = PieceColor.white;
    whiteKingMoved = false;
    blackKingMoved = false;
    whiteRookAMoved = false;
    whiteRookHMoved = false;
    blackRookAMoved = false;
    blackRookHMoved = false;
    enPassantTarget = null;
    capturedByWhite.clear();
    capturedByBlack.clear();
  }

  static int row(int index) => index ~/ 8;
  static int col(int index) => index % 8;
  static int indexOf(int r, int c) => r * 8 + c;
  static bool inBounds(int r, int c) => r >= 0 && r < 8 && c >= 0 && c < 8;

  ChessPiece? pieceAt(int index) => board[index];

  /// Movimientos legales de la pieza en [index]: solo se devuelven si es el
  /// turno del color de esa pieza y si no dejan al propio rey en jaque.
  List<ChessMove> legalMovesFrom(int index) {
    final piece = board[index];
    if (piece == null || piece.color != turn) return [];
    return _pseudoLegalMoves(index)
        .where((m) => _isMoveSafe(m, piece.color))
        .toList();
  }

  List<ChessMove> allLegalMoves(PieceColor color) {
    final moves = <ChessMove>[];
    for (int i = 0; i < 64; i++) {
      final piece = board[i];
      if (piece == null || piece.color != color) continue;
      moves.addAll(
        _pseudoLegalMoves(i).where((m) => _isMoveSafe(m, color)),
      );
    }
    return moves;
  }

  /// Aplica un movimiento (debe provenir de [legalMovesFrom]) y cambia el turno.
  /// Devuelve la pieza capturada, si la hubo.
  ChessPiece? makeMove(ChessMove move) {
    final captured = _applyMove(move, simulate: false);
    turn = turn == PieceColor.white ? PieceColor.black : PieceColor.white;
    return captured;
  }

  bool isInCheck(PieceColor color) {
    final kingIndex = _findKing(color);
    if (kingIndex == -1) return false;
    final opponent = _opponent(color);
    return isSquareAttacked(kingIndex, opponent);
  }

  GameStatus get status {
    final inCheck = isInCheck(turn);
    final hasMoves = allLegalMoves(turn).isNotEmpty;
    if (!hasMoves) {
      return inCheck ? GameStatus.checkmate : GameStatus.stalemate;
    }
    return inCheck ? GameStatus.check : GameStatus.playing;
  }

  PieceColor _opponent(PieceColor color) =>
      color == PieceColor.white ? PieceColor.black : PieceColor.white;

  int _findKing(PieceColor color) {
    for (int i = 0; i < 64; i++) {
      final p = board[i];
      if (p != null && p.type == PieceType.king && p.color == color) return i;
    }
    return -1;
  }

  bool isSquareAttacked(int index, PieceColor byColor) {
    for (int i = 0; i < 64; i++) {
      final piece = board[i];
      if (piece == null || piece.color != byColor) continue;

      if (piece.type == PieceType.pawn) {
        final dir = piece.color == PieceColor.white ? -1 : 1;
        final r = row(i), c = col(i);
        for (final dc in [-1, 1]) {
          final nr = r + dir, nc = c + dc;
          if (inBounds(nr, nc) && indexOf(nr, nc) == index) return true;
        }
        continue;
      }

      // Para el rey excluimos el enroque para no recursar infinitamente.
      final moves = piece.type == PieceType.king
          ? _kingMoves(i, piece, includeCastling: false)
          : _pseudoLegalMoves(i);
      if (moves.any((m) => m.to == index)) return true;
    }
    return false;
  }

  bool _isMoveSafe(ChessMove move, PieceColor color) {
    final snapshot = _snapshot();
    _applyMove(move, simulate: true);
    final safe = !isInCheck(color);
    _restore(snapshot);
    return safe;
  }

  List<ChessMove> _pseudoLegalMoves(int index) {
    final piece = board[index];
    if (piece == null) return [];
    switch (piece.type) {
      case PieceType.pawn:
        return _pawnMoves(index, piece);
      case PieceType.knight:
        return _knightMoves(index, piece);
      case PieceType.bishop:
        return _slidingMoves(index, piece, const [
          [-1, -1],
          [-1, 1],
          [1, -1],
          [1, 1],
        ]);
      case PieceType.rook:
        return _slidingMoves(index, piece, const [
          [-1, 0],
          [1, 0],
          [0, -1],
          [0, 1],
        ]);
      case PieceType.queen:
        return _slidingMoves(index, piece, const [
          [-1, -1],
          [-1, 1],
          [1, -1],
          [1, 1],
          [-1, 0],
          [1, 0],
          [0, -1],
          [0, 1],
        ]);
      case PieceType.king:
        return _kingMoves(index, piece);
    }
  }

  List<ChessMove> _pawnMoves(int index, ChessPiece piece) {
    final moves = <ChessMove>[];
    final r = row(index), c = col(index);
    final dir = piece.color == PieceColor.white ? -1 : 1;
    final startRow = piece.color == PieceColor.white ? 6 : 1;
    final promotionRow = piece.color == PieceColor.white ? 0 : 7;

    void addPawnMove(int to) {
      if (row(to) == promotionRow) {
        for (final promo in const [
          PieceType.queen,
          PieceType.rook,
          PieceType.bishop,
          PieceType.knight,
        ]) {
          moves.add(ChessMove(index, to, promotion: promo));
        }
      } else {
        moves.add(ChessMove(index, to));
      }
    }

    // Avance recto
    if (inBounds(r + dir, c) && board[indexOf(r + dir, c)] == null) {
      addPawnMove(indexOf(r + dir, c));
      if (r == startRow && board[indexOf(r + 2 * dir, c)] == null) {
        moves.add(ChessMove(index, indexOf(r + 2 * dir, c)));
      }
    }

    // Capturas (incluye al paso)
    for (final dc in [-1, 1]) {
      final nr = r + dir, nc = c + dc;
      if (!inBounds(nr, nc)) continue;
      final target = indexOf(nr, nc);
      final targetPiece = board[target];
      if (targetPiece != null && targetPiece.color != piece.color) {
        addPawnMove(target);
      } else if (targetPiece == null && target == enPassantTarget) {
        moves.add(ChessMove(index, target));
      }
    }

    return moves;
  }

  List<ChessMove> _knightMoves(int index, ChessPiece piece) {
    const offsets = [
      [-2, -1],
      [-2, 1],
      [-1, -2],
      [-1, 2],
      [1, -2],
      [1, 2],
      [2, -1],
      [2, 1],
    ];
    final moves = <ChessMove>[];
    final r = row(index), c = col(index);
    for (final o in offsets) {
      final nr = r + o[0], nc = c + o[1];
      if (!inBounds(nr, nc)) continue;
      final target = indexOf(nr, nc);
      final targetPiece = board[target];
      if (targetPiece == null || targetPiece.color != piece.color) {
        moves.add(ChessMove(index, target));
      }
    }
    return moves;
  }

  List<ChessMove> _slidingMoves(
    int index,
    ChessPiece piece,
    List<List<int>> directions,
  ) {
    final moves = <ChessMove>[];
    final r = row(index), c = col(index);
    for (final d in directions) {
      int nr = r + d[0], nc = c + d[1];
      while (inBounds(nr, nc)) {
        final target = indexOf(nr, nc);
        final targetPiece = board[target];
        if (targetPiece == null) {
          moves.add(ChessMove(index, target));
        } else {
          if (targetPiece.color != piece.color) {
            moves.add(ChessMove(index, target));
          }
          break;
        }
        nr += d[0];
        nc += d[1];
      }
    }
    return moves;
  }

  List<ChessMove> _kingMoves(
    int index,
    ChessPiece piece, {
    bool includeCastling = true,
  }) {
    final moves = <ChessMove>[];
    final r = row(index), c = col(index);
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final nr = r + dr, nc = c + dc;
        if (!inBounds(nr, nc)) continue;
        final target = indexOf(nr, nc);
        final targetPiece = board[target];
        if (targetPiece == null || targetPiece.color != piece.color) {
          moves.add(ChessMove(index, target));
        }
      }
    }
    if (includeCastling) {
      moves.addAll(_castlingMoves(index, piece));
    }
    return moves;
  }

  List<ChessMove> _castlingMoves(int kingIndex, ChessPiece king) {
    final moves = <ChessMove>[];
    final color = king.color;
    final kingMoved =
        color == PieceColor.white ? whiteKingMoved : blackKingMoved;
    if (kingMoved) return moves;
    if (isInCheck(color)) return moves;

    final homeRow = color == PieceColor.white ? 7 : 0;
    if (row(kingIndex) != homeRow || col(kingIndex) != 4) return moves;

    final rookAMoved =
        color == PieceColor.white ? whiteRookAMoved : blackRookAMoved;
    final rookHMoved =
        color == PieceColor.white ? whiteRookHMoved : blackRookHMoved;
    final opponent = _opponent(color);

    // Enroque corto (torre de columna h)
    if (!rookHMoved) {
      final rook = board[indexOf(homeRow, 7)];
      if (rook != null && rook.type == PieceType.rook && rook.color == color) {
        final f = indexOf(homeRow, 5);
        final g = indexOf(homeRow, 6);
        if (board[f] == null &&
            board[g] == null &&
            !isSquareAttacked(f, opponent) &&
            !isSquareAttacked(g, opponent)) {
          moves.add(ChessMove(kingIndex, g));
        }
      }
    }

    // Enroque largo (torre de columna a)
    if (!rookAMoved) {
      final rook = board[indexOf(homeRow, 0)];
      if (rook != null && rook.type == PieceType.rook && rook.color == color) {
        final d = indexOf(homeRow, 3);
        final cSq = indexOf(homeRow, 2);
        final b = indexOf(homeRow, 1);
        if (board[d] == null &&
            board[cSq] == null &&
            board[b] == null &&
            !isSquareAttacked(d, opponent) &&
            !isSquareAttacked(cSq, opponent)) {
          moves.add(ChessMove(kingIndex, cSq));
        }
      }
    }

    return moves;
  }

  ChessPiece? _applyMove(ChessMove move, {required bool simulate}) {
    final piece = board[move.from]!;
    ChessPiece? captured = board[move.to];

    // Captura al paso: la casilla destino está vacía pero el peón capturado
    // está en la misma fila que el peón que se mueve.
    if (piece.type == PieceType.pawn &&
        captured == null &&
        move.to == enPassantTarget &&
        col(move.from) != col(move.to)) {
      final capturedIndex = indexOf(row(move.from), col(move.to));
      captured = board[capturedIndex];
      board[capturedIndex] = null;
    }

    board[move.to] =
        move.promotion != null ? ChessPiece(move.promotion!, piece.color) : piece;
    board[move.from] = null;

    // Enroque: mover también la torre.
    if (piece.type == PieceType.king && (move.to - move.from).abs() == 2) {
      final r = row(move.from);
      if (col(move.to) == 6) {
        board[indexOf(r, 5)] = board[indexOf(r, 7)];
        board[indexOf(r, 7)] = null;
      } else if (col(move.to) == 2) {
        board[indexOf(r, 3)] = board[indexOf(r, 0)];
        board[indexOf(r, 0)] = null;
      }
    }

    if (!simulate) {
      _updateCastlingRights(piece, move);

      if (piece.type == PieceType.pawn && (move.from - move.to).abs() == 16) {
        enPassantTarget =
            indexOf((row(move.from) + row(move.to)) ~/ 2, col(move.from));
      } else {
        enPassantTarget = null;
      }

      if (captured != null) {
        if (piece.color == PieceColor.white) {
          capturedByWhite.add(captured);
        } else {
          capturedByBlack.add(captured);
        }
      }
    }

    return captured;
  }

  void _updateCastlingRights(ChessPiece piece, ChessMove move) {
    if (piece.type == PieceType.king) {
      if (piece.color == PieceColor.white) {
        whiteKingMoved = true;
      } else {
        blackKingMoved = true;
      }
    }
    if (move.from == indexOf(7, 0) || move.to == indexOf(7, 0)) {
      whiteRookAMoved = true;
    }
    if (move.from == indexOf(7, 7) || move.to == indexOf(7, 7)) {
      whiteRookHMoved = true;
    }
    if (move.from == indexOf(0, 0) || move.to == indexOf(0, 0)) {
      blackRookAMoved = true;
    }
    if (move.from == indexOf(0, 7) || move.to == indexOf(0, 7)) {
      blackRookHMoved = true;
    }
  }

  _BoardSnapshot _snapshot() => _BoardSnapshot(
        board: List<ChessPiece?>.from(board),
        enPassantTarget: enPassantTarget,
        whiteKingMoved: whiteKingMoved,
        blackKingMoved: blackKingMoved,
        whiteRookAMoved: whiteRookAMoved,
        whiteRookHMoved: whiteRookHMoved,
        blackRookAMoved: blackRookAMoved,
        blackRookHMoved: blackRookHMoved,
      );

  void _restore(_BoardSnapshot s) {
    board = s.board;
    enPassantTarget = s.enPassantTarget;
    whiteKingMoved = s.whiteKingMoved;
    blackKingMoved = s.blackKingMoved;
    whiteRookAMoved = s.whiteRookAMoved;
    whiteRookHMoved = s.whiteRookHMoved;
    blackRookAMoved = s.blackRookAMoved;
    blackRookHMoved = s.blackRookHMoved;
  }
}
