import 'package:ajedrez_seed_app/chess/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

ChessMove _find(ChessEngine e, int from, int to) {
  final matches = e.legalMovesFrom(from).where((m) => m.to == to).toList();
  expect(matches, isNotEmpty, reason: 'move $from->$to should be legal');
  return matches.first;
}

void main() {
  group('posición inicial', () {
    test('las blancas tienen 20 movimientos legales', () {
      final engine = ChessEngine();
      expect(engine.allLegalMoves(PieceColor.white).length, 20);
    });

    test('no se puede mover una pieza fuera de turno', () {
      final engine = ChessEngine();
      // Peón negro (fila 1) aunque le toque a blancas.
      expect(engine.legalMovesFrom(8), isEmpty);
    });
  });

  group('movimientos básicos', () {
    test('el peón puede avanzar una o dos casillas desde su inicio', () {
      final engine = ChessEngine();
      final targets = engine.legalMovesFrom(52).map((m) => m.to).toSet();
      expect(targets, {44, 36});
    });

    test('una pieza no puede saltar sobre otras (torre bloqueada)', () {
      final engine = ChessEngine();
      // Torre blanca en 56, peón blanco delante en 48: sin movimientos.
      expect(engine.legalMovesFrom(56), isEmpty);
    });
  });

  group('jaque y jaque mate', () {
    test('mate pastor (scholar\'s mate) termina la partida', () {
      final engine = ChessEngine();
      engine.makeMove(_find(engine, 52, 36)); // e2-e4
      engine.makeMove(_find(engine, 12, 28)); // e7-e5
      engine.makeMove(_find(engine, 61, 34)); // Bc4
      engine.makeMove(_find(engine, 1, 18)); // Cb8-c6
      engine.makeMove(_find(engine, 59, 31)); // Qh5
      engine.makeMove(_find(engine, 6, 21)); // Cg8-f6 (no defiende f7)
      engine.makeMove(_find(engine, 31, 13)); // Qxf7#

      expect(engine.status, GameStatus.checkmate);
      expect(engine.allLegalMoves(PieceColor.black), isEmpty);
    });

    test('un rey en jaque solo puede mover a casillas que resuelven el jaque', () {
      final engine = ChessEngine();
      engine.board = List<ChessPiece?>.filled(64, null);
      engine.board[3] = const ChessPiece(PieceType.king, PieceColor.black); // d8
      engine.board[35] = const ChessPiece(PieceType.queen, PieceColor.white); // d4
      engine.board[60] = const ChessPiece(PieceType.king, PieceColor.white); // e1
      engine.turn = PieceColor.black;

      expect(engine.isInCheck(PieceColor.black), isTrue);

      final kingMoves = engine.legalMovesFrom(3).map((m) => m.to).toSet();
      // d7 (índice 11) sigue en la columna de la dama: no resuelve el jaque.
      expect(kingMoves.contains(11), isFalse);
      // c8 y e8 salen de la columna/diagonales de la dama: sí son legales.
      expect(kingMoves.contains(2), isTrue);
      expect(kingMoves.contains(4), isTrue);
    });
  });

  group('enroque', () {
    test('enroque corto blanco es legal cuando el camino está despejado', () {
      final engine = ChessEngine();
      engine.makeMove(_find(engine, 52, 36)); // e4
      engine.makeMove(_find(engine, 12, 28)); // e5
      engine.makeMove(_find(engine, 62, 45)); // Cg1-f3
      engine.makeMove(_find(engine, 1, 18)); // Cb8-c6
      engine.makeMove(_find(engine, 61, 34)); // Bc4
      engine.makeMove(_find(engine, 6, 21)); // Cg8-f6

      final castling = engine
          .legalMovesFrom(60)
          .where((m) => m.to == 62)
          .toList();
      expect(castling, isNotEmpty);

      engine.makeMove(castling.first);
      expect(engine.pieceAt(62)?.type, PieceType.king);
      expect(engine.pieceAt(61)?.type, PieceType.rook);
      expect(engine.pieceAt(60), isNull);
      expect(engine.pieceAt(63), isNull);
    });
  });

  group('captura al paso', () {
    test('un peón puede capturar al paso justo después del avance doble', () {
      final engine = ChessEngine();
      engine.makeMove(_find(engine, 52, 36)); // e4
      engine.makeMove(_find(engine, 9, 17)); // b7-b6 (relleno)
      engine.makeMove(_find(engine, 36, 28)); // e5
      engine.makeMove(_find(engine, 11, 27)); // d7-d5 (avance doble junto al peón blanco)

      final enPassant = engine.legalMovesFrom(28).where((m) => m.to == 19).toList();
      expect(enPassant, isNotEmpty);

      engine.makeMove(enPassant.first);
      expect(engine.pieceAt(19)?.color, PieceColor.white);
      expect(engine.pieceAt(27), isNull); // peón negro capturado
    });
  });

  group('promoción', () {
    test('un peón que llega a la última fila ofrece opciones de promoción', () {
      final engine = ChessEngine();
      // Colocamos manualmente un peón blanco a un paso de coronar.
      engine.board = List<ChessPiece?>.filled(64, null);
      engine.board[0] = const ChessPiece(PieceType.king, PieceColor.black);
      engine.board[60] = const ChessPiece(PieceType.king, PieceColor.white);
      engine.board[12] = const ChessPiece(PieceType.pawn, PieceColor.white);
      engine.turn = PieceColor.white;

      final promotions = engine.legalMovesFrom(12).where((m) => m.to == 4).toList();
      expect(promotions.map((m) => m.promotion).toSet(), {
        PieceType.queen,
        PieceType.rook,
        PieceType.bishop,
        PieceType.knight,
      });
    });
  });
}
