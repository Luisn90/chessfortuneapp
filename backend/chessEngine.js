// Motor de reglas de ajedrez del servidor (autoridad de la partida).
//
// Es un port fiel de lib/chess/chess_engine.dart: mismo esquema de tablero
// (índice 0..63, fila = index/8, columna = index%8; fila 0 = negras arriba,
// fila 7 = blancas abajo) y misma lógica de generación de movimientos, para
// que el servidor pueda validar exactamente lo mismo que valida cada cliente.

const PieceColor = { WHITE: 'white', BLACK: 'black' };
const PieceType = {
    PAWN: 'pawn',
    KNIGHT: 'knight',
    BISHOP: 'bishop',
    ROOK: 'rook',
    QUEEN: 'queen',
    KING: 'king',
};

function opponent(color) {
    return color === PieceColor.WHITE ? PieceColor.BLACK : PieceColor.WHITE;
}

function row(index) { return Math.floor(index / 8); }
function col(index) { return index % 8; }
function indexOf(r, c) { return r * 8 + c; }
function inBounds(r, c) { return r >= 0 && r < 8 && c >= 0 && c < 8; }

class ChessEngine {
    constructor() {
        this.reset();
    }

    reset() {
        this.board = new Array(64).fill(null);
        const backRank = [
            PieceType.ROOK, PieceType.KNIGHT, PieceType.BISHOP, PieceType.QUEEN,
            PieceType.KING, PieceType.BISHOP, PieceType.KNIGHT, PieceType.ROOK,
        ];
        for (let c = 0; c < 8; c++) {
            this.board[c] = { type: backRank[c], color: PieceColor.BLACK };
            this.board[8 + c] = { type: PieceType.PAWN, color: PieceColor.BLACK };
            this.board[48 + c] = { type: PieceType.PAWN, color: PieceColor.WHITE };
            this.board[56 + c] = { type: backRank[c], color: PieceColor.WHITE };
        }
        this.turn = PieceColor.WHITE;
        this.whiteKingMoved = false;
        this.blackKingMoved = false;
        this.whiteRookAMoved = false;
        this.whiteRookHMoved = false;
        this.blackRookAMoved = false;
        this.blackRookHMoved = false;
        this.enPassantTarget = null;
    }

    pieceAt(index) { return this.board[index]; }

    legalMovesFrom(index) {
        const piece = this.board[index];
        if (!piece || piece.color !== this.turn) return [];
        return this._pseudoLegalMoves(index).filter((m) => this._isMoveSafe(m, piece.color));
    }

    allLegalMoves(color) {
        const moves = [];
        for (let i = 0; i < 64; i++) {
            const piece = this.board[i];
            if (!piece || piece.color !== color) continue;
            for (const m of this._pseudoLegalMoves(i)) {
                if (this._isMoveSafe(m, color)) moves.push(m);
            }
        }
        return moves;
    }

    makeMove(move) {
        const captured = this._applyMove(move, false);
        this.turn = opponent(this.turn);
        return captured;
    }

    isInCheck(color) {
        const kingIndex = this._findKing(color);
        if (kingIndex === -1) return false;
        return this.isSquareAttacked(kingIndex, opponent(color));
    }

    get status() {
        const inCheck = this.isInCheck(this.turn);
        const hasMoves = this.allLegalMoves(this.turn).length > 0;
        if (!hasMoves) return inCheck ? 'checkmate' : 'stalemate';
        return inCheck ? 'check' : 'playing';
    }

    _findKing(color) {
        for (let i = 0; i < 64; i++) {
            const p = this.board[i];
            if (p && p.type === PieceType.KING && p.color === color) return i;
        }
        return -1;
    }

    isSquareAttacked(index, byColor) {
        for (let i = 0; i < 64; i++) {
            const piece = this.board[i];
            if (!piece || piece.color !== byColor) continue;

            if (piece.type === PieceType.PAWN) {
                const dir = piece.color === PieceColor.WHITE ? -1 : 1;
                const r = row(i), c = col(i);
                for (const dc of [-1, 1]) {
                    const nr = r + dir, nc = c + dc;
                    if (inBounds(nr, nc) && indexOf(nr, nc) === index) return true;
                }
                continue;
            }

            const moves = piece.type === PieceType.KING
                ? this._kingMoves(i, piece, false)
                : this._pseudoLegalMoves(i);
            if (moves.some((m) => m.to === index)) return true;
        }
        return false;
    }

    _isMoveSafe(move, color) {
        const snapshot = this._snapshot();
        this._applyMove(move, true);
        const safe = !this.isInCheck(color);
        this._restore(snapshot);
        return safe;
    }

    _pseudoLegalMoves(index) {
        const piece = this.board[index];
        if (!piece) return [];
        switch (piece.type) {
            case PieceType.PAWN: return this._pawnMoves(index, piece);
            case PieceType.KNIGHT: return this._knightMoves(index, piece);
            case PieceType.BISHOP: return this._slidingMoves(index, piece, [[-1, -1], [-1, 1], [1, -1], [1, 1]]);
            case PieceType.ROOK: return this._slidingMoves(index, piece, [[-1, 0], [1, 0], [0, -1], [0, 1]]);
            case PieceType.QUEEN: return this._slidingMoves(index, piece, [
                [-1, -1], [-1, 1], [1, -1], [1, 1], [-1, 0], [1, 0], [0, -1], [0, 1],
            ]);
            case PieceType.KING: return this._kingMoves(index, piece, true);
            default: return [];
        }
    }

    _pawnMoves(index, piece) {
        const moves = [];
        const r = row(index), c = col(index);
        const dir = piece.color === PieceColor.WHITE ? -1 : 1;
        const startRow = piece.color === PieceColor.WHITE ? 6 : 1;
        const promotionRow = piece.color === PieceColor.WHITE ? 0 : 7;

        const addPawnMove = (to) => {
            if (row(to) === promotionRow) {
                for (const promo of [PieceType.QUEEN, PieceType.ROOK, PieceType.BISHOP, PieceType.KNIGHT]) {
                    moves.push({ from: index, to, promotion: promo });
                }
            } else {
                moves.push({ from: index, to, promotion: null });
            }
        };

        if (inBounds(r + dir, c) && !this.board[indexOf(r + dir, c)]) {
            addPawnMove(indexOf(r + dir, c));
            if (r === startRow && !this.board[indexOf(r + 2 * dir, c)]) {
                moves.push({ from: index, to: indexOf(r + 2 * dir, c), promotion: null });
            }
        }

        for (const dc of [-1, 1]) {
            const nr = r + dir, nc = c + dc;
            if (!inBounds(nr, nc)) continue;
            const target = indexOf(nr, nc);
            const targetPiece = this.board[target];
            if (targetPiece && targetPiece.color !== piece.color) {
                addPawnMove(target);
            } else if (!targetPiece && target === this.enPassantTarget) {
                moves.push({ from: index, to: target, promotion: null });
            }
        }

        return moves;
    }

    _knightMoves(index, piece) {
        const offsets = [[-2, -1], [-2, 1], [-1, -2], [-1, 2], [1, -2], [1, 2], [2, -1], [2, 1]];
        const moves = [];
        const r = row(index), c = col(index);
        for (const [dr, dc] of offsets) {
            const nr = r + dr, nc = c + dc;
            if (!inBounds(nr, nc)) continue;
            const target = indexOf(nr, nc);
            const targetPiece = this.board[target];
            if (!targetPiece || targetPiece.color !== piece.color) {
                moves.push({ from: index, to: target, promotion: null });
            }
        }
        return moves;
    }

    _slidingMoves(index, piece, directions) {
        const moves = [];
        const r = row(index), c = col(index);
        for (const [dr, dc] of directions) {
            let nr = r + dr, nc = c + dc;
            while (inBounds(nr, nc)) {
                const target = indexOf(nr, nc);
                const targetPiece = this.board[target];
                if (!targetPiece) {
                    moves.push({ from: index, to: target, promotion: null });
                } else {
                    if (targetPiece.color !== piece.color) {
                        moves.push({ from: index, to: target, promotion: null });
                    }
                    break;
                }
                nr += dr;
                nc += dc;
            }
        }
        return moves;
    }

    _kingMoves(index, piece, includeCastling) {
        const moves = [];
        const r = row(index), c = col(index);
        for (let dr = -1; dr <= 1; dr++) {
            for (let dc = -1; dc <= 1; dc++) {
                if (dr === 0 && dc === 0) continue;
                const nr = r + dr, nc = c + dc;
                if (!inBounds(nr, nc)) continue;
                const target = indexOf(nr, nc);
                const targetPiece = this.board[target];
                if (!targetPiece || targetPiece.color !== piece.color) {
                    moves.push({ from: index, to: target, promotion: null });
                }
            }
        }
        if (includeCastling) moves.push(...this._castlingMoves(index, piece));
        return moves;
    }

    _castlingMoves(kingIndex, king) {
        const moves = [];
        const color = king.color;
        const kingMoved = color === PieceColor.WHITE ? this.whiteKingMoved : this.blackKingMoved;
        if (kingMoved) return moves;
        if (this.isInCheck(color)) return moves;

        const homeRow = color === PieceColor.WHITE ? 7 : 0;
        if (row(kingIndex) !== homeRow || col(kingIndex) !== 4) return moves;

        const rookAMoved = color === PieceColor.WHITE ? this.whiteRookAMoved : this.blackRookAMoved;
        const rookHMoved = color === PieceColor.WHITE ? this.whiteRookHMoved : this.blackRookHMoved;
        const opp = opponent(color);

        if (!rookHMoved) {
            const rook = this.board[indexOf(homeRow, 7)];
            if (rook && rook.type === PieceType.ROOK && rook.color === color) {
                const f = indexOf(homeRow, 5), g = indexOf(homeRow, 6);
                if (!this.board[f] && !this.board[g] &&
                    !this.isSquareAttacked(f, opp) && !this.isSquareAttacked(g, opp)) {
                    moves.push({ from: kingIndex, to: g, promotion: null });
                }
            }
        }

        if (!rookAMoved) {
            const rook = this.board[indexOf(homeRow, 0)];
            if (rook && rook.type === PieceType.ROOK && rook.color === color) {
                const d = indexOf(homeRow, 3), cSq = indexOf(homeRow, 2), b = indexOf(homeRow, 1);
                if (!this.board[d] && !this.board[cSq] && !this.board[b] &&
                    !this.isSquareAttacked(d, opp) && !this.isSquareAttacked(cSq, opp)) {
                    moves.push({ from: kingIndex, to: cSq, promotion: null });
                }
            }
        }

        return moves;
    }

    _applyMove(move, simulate) {
        const piece = this.board[move.from];
        let captured = this.board[move.to];

        if (piece.type === PieceType.PAWN && !captured && move.to === this.enPassantTarget &&
            col(move.from) !== col(move.to)) {
            const capturedIndex = indexOf(row(move.from), col(move.to));
            captured = this.board[capturedIndex];
            this.board[capturedIndex] = null;
        }

        this.board[move.to] = move.promotion ? { type: move.promotion, color: piece.color } : piece;
        this.board[move.from] = null;

        if (piece.type === PieceType.KING && Math.abs(move.to - move.from) === 2) {
            const r = row(move.from);
            if (col(move.to) === 6) {
                this.board[indexOf(r, 5)] = this.board[indexOf(r, 7)];
                this.board[indexOf(r, 7)] = null;
            } else if (col(move.to) === 2) {
                this.board[indexOf(r, 3)] = this.board[indexOf(r, 0)];
                this.board[indexOf(r, 0)] = null;
            }
        }

        if (!simulate) {
            this._updateCastlingRights(piece, move);

            if (piece.type === PieceType.PAWN && Math.abs(move.from - move.to) === 16) {
                this.enPassantTarget = indexOf(Math.floor((row(move.from) + row(move.to)) / 2), col(move.from));
            } else {
                this.enPassantTarget = null;
            }
        }

        return captured;
    }

    _updateCastlingRights(piece, move) {
        if (piece.type === PieceType.KING) {
            if (piece.color === PieceColor.WHITE) this.whiteKingMoved = true;
            else this.blackKingMoved = true;
        }
        if (move.from === indexOf(7, 0) || move.to === indexOf(7, 0)) this.whiteRookAMoved = true;
        if (move.from === indexOf(7, 7) || move.to === indexOf(7, 7)) this.whiteRookHMoved = true;
        if (move.from === indexOf(0, 0) || move.to === indexOf(0, 0)) this.blackRookAMoved = true;
        if (move.from === indexOf(0, 7) || move.to === indexOf(0, 7)) this.blackRookHMoved = true;
    }

    _snapshot() {
        return {
            board: this.board.map((p) => (p ? { ...p } : null)),
            enPassantTarget: this.enPassantTarget,
            whiteKingMoved: this.whiteKingMoved,
            blackKingMoved: this.blackKingMoved,
            whiteRookAMoved: this.whiteRookAMoved,
            whiteRookHMoved: this.whiteRookHMoved,
            blackRookAMoved: this.blackRookAMoved,
            blackRookHMoved: this.blackRookHMoved,
        };
    }

    _restore(s) {
        this.board = s.board;
        this.enPassantTarget = s.enPassantTarget;
        this.whiteKingMoved = s.whiteKingMoved;
        this.blackKingMoved = s.blackKingMoved;
        this.whiteRookAMoved = s.whiteRookAMoved;
        this.whiteRookHMoved = s.whiteRookHMoved;
        this.blackRookAMoved = s.blackRookAMoved;
        this.blackRookHMoved = s.blackRookHMoved;
    }
}

module.exports = { ChessEngine, PieceColor, PieceType };
