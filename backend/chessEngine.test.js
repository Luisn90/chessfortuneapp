const assert = require('assert');
const { ChessEngine } = require('./chessEngine');

function find(engine, from, to) {
    const m = engine.legalMovesFrom(from).find((mv) => mv.to === to);
    assert.ok(m, `move ${from}->${to} should be legal`);
    return m;
}

function test(name, fn) {
    try {
        fn();
        console.log('OK  -', name);
    } catch (err) {
        console.error('FAIL -', name);
        console.error(err);
        process.exitCode = 1;
    }
}

test('las blancas tienen 20 movimientos legales en la posición inicial', () => {
    const engine = new ChessEngine();
    assert.strictEqual(engine.allLegalMoves('white').length, 20);
});

test('no se puede mover una pieza fuera de turno', () => {
    const engine = new ChessEngine();
    assert.strictEqual(engine.legalMovesFrom(8).length, 0);
});

test('el peón puede avanzar una o dos casillas desde su inicio', () => {
    const engine = new ChessEngine();
    const targets = engine.legalMovesFrom(52).map((m) => m.to).sort();
    assert.deepStrictEqual(targets, [36, 44]);
});

test('una torre bloqueada no tiene movimientos', () => {
    const engine = new ChessEngine();
    assert.strictEqual(engine.legalMovesFrom(56).length, 0);
});

test('mate pastor (scholar\'s mate) termina la partida', () => {
    const engine = new ChessEngine();
    engine.makeMove(find(engine, 52, 36)); // e4
    engine.makeMove(find(engine, 12, 28)); // e5
    engine.makeMove(find(engine, 61, 34)); // Bc4
    engine.makeMove(find(engine, 1, 18));  // Nc6
    engine.makeMove(find(engine, 59, 31)); // Qh5
    engine.makeMove(find(engine, 6, 21));  // Nf6
    engine.makeMove(find(engine, 31, 13)); // Qxf7#

    assert.strictEqual(engine.status, 'checkmate');
    assert.strictEqual(engine.allLegalMoves('black').length, 0);
});

test('un rey en jaque solo puede mover a casillas que resuelven el jaque', () => {
    const engine = new ChessEngine();
    engine.board = new Array(64).fill(null);
    engine.board[3] = { type: 'king', color: 'black' };
    engine.board[35] = { type: 'queen', color: 'white' };
    engine.board[60] = { type: 'king', color: 'white' };
    engine.turn = 'black';

    assert.strictEqual(engine.isInCheck('black'), true);
    const kingMoves = engine.legalMovesFrom(3).map((m) => m.to);
    assert.ok(!kingMoves.includes(11));
    assert.ok(kingMoves.includes(2));
    assert.ok(kingMoves.includes(4));
});

test('enroque corto blanco es legal cuando el camino está despejado', () => {
    const engine = new ChessEngine();
    engine.makeMove(find(engine, 52, 36)); // e4
    engine.makeMove(find(engine, 12, 28)); // e5
    engine.makeMove(find(engine, 62, 45)); // Nf3
    engine.makeMove(find(engine, 1, 18));  // Nc6
    engine.makeMove(find(engine, 61, 34)); // Bc4
    engine.makeMove(find(engine, 6, 21));  // Nf6

    const castling = engine.legalMovesFrom(60).find((m) => m.to === 62);
    assert.ok(castling);
    engine.makeMove(castling);
    assert.strictEqual(engine.pieceAt(62).type, 'king');
    assert.strictEqual(engine.pieceAt(61).type, 'rook');
    assert.strictEqual(engine.pieceAt(60), null);
    assert.strictEqual(engine.pieceAt(63), null);
});

test('un peón puede capturar al paso justo después del avance doble', () => {
    const engine = new ChessEngine();
    engine.makeMove(find(engine, 52, 36)); // e4
    engine.makeMove(find(engine, 9, 17));  // b6
    engine.makeMove(find(engine, 36, 28)); // e5
    engine.makeMove(find(engine, 11, 27)); // d5

    const enPassant = engine.legalMovesFrom(28).find((m) => m.to === 19);
    assert.ok(enPassant);
    engine.makeMove(enPassant);
    assert.strictEqual(engine.pieceAt(19).color, 'white');
    assert.strictEqual(engine.pieceAt(27), null);
});

test('un peón que llega a la última fila ofrece opciones de promoción', () => {
    const engine = new ChessEngine();
    engine.board = new Array(64).fill(null);
    engine.board[0] = { type: 'king', color: 'black' };
    engine.board[60] = { type: 'king', color: 'white' };
    engine.board[12] = { type: 'pawn', color: 'white' };
    engine.turn = 'white';

    const promotions = engine.legalMovesFrom(12).filter((m) => m.to === 4).map((m) => m.promotion).sort();
    assert.deepStrictEqual(promotions, ['bishop', 'knight', 'queen', 'rook']);
});

if (process.exitCode) {
    console.error('\nAlgunas pruebas fallaron.');
} else {
    console.log('\nTodas las pruebas pasaron.');
}
