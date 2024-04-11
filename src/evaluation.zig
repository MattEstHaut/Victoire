//! Contains heuristic evaluation functions.

const chess = @import("chess.zig");
const squares = @import("squares.zig");
const tables = @import("pst.zig");
const movegen = @import("movegen.zig");

pub const checkmate: i64 = 1_000_000;
pub const stalemate: i64 = 0;

inline fn value(piece: chess.Piece, spst: tables.SidePieceSquareTables, index: usize) i64 {
    return switch (piece) {
        .pawn => spst.pawn[index] + 100,
        .knight => spst.knight[index] + 320,
        .bishop => spst.bishop[index] + 320,
        .rook => spst.rook[index] + 500,
        .queen => spst.queen[index] + 900,
        .king => spst.king[index],
    };
}

inline fn mul(color: chess.Color) i64 {
    return if (color == .white) 1 else -1;
}

pub const Evaluator = struct {
    opening_score: i64 = 0,
    endgame_score: i64 = 0,
    pieces_phase: i64 = 24,
    phase: i64 = 0,
    side: chess.Color = .white,

    pub fn init(board: chess.Board) Evaluator {
        var evaluator = Evaluator{};
        var mutable_board = board;

        evaluator.side = board.side;

        evaluator.pieces_phase -= @popCount(mutable_board.white.knights);
        evaluator.pieces_phase -= @popCount(mutable_board.black.knights);
        evaluator.pieces_phase -= @popCount(mutable_board.white.bishops);
        evaluator.pieces_phase -= @popCount(mutable_board.black.bishops);
        evaluator.pieces_phase -= @popCount(mutable_board.white.rooks) * 2;
        evaluator.pieces_phase -= @popCount(mutable_board.black.rooks) * 2;
        evaluator.pieces_phase -= @popCount(mutable_board.white.queens) * 4;
        evaluator.pieces_phase -= @popCount(mutable_board.black.queens) * 4;
        evaluator.phase = @divTrunc(evaluator.pieces_phase * 256 + 12, 24);

        for (0..64) |i| {
            const mask = @as(u64, 1) << @intCast(i);
            var color = chess.Color.white;

            const piece = mutable_board.white.collision(mask) orelse blk: {
                color = .black;
                break :blk mutable_board.black.collision(mask);
            } orelse continue;

            evaluator.opening_score += mul(color) * value(piece, tables.opening.get(color), i);
            evaluator.endgame_score += mul(color) * value(piece, tables.endgame.get(color), i);
        }

        return evaluator;
    }

    pub inline fn next(self: Evaluator, move: chess.Move) Evaluator {
        var result = self;
        result.side = result.side.other();
        if (move.null_move) return result;
        const m = mul(move.side);

        result.opening_score -= m * value(move.piece, tables.opening.get(move.side), @ctz(move.src));
        result.endgame_score -= m * value(move.piece, tables.endgame.get(move.side), @ctz(move.src));

        {
            const piece = if (move.promotion == null) move.piece else move.promotion.?.piece();
            result.opening_score += m * value(piece, tables.opening.get(move.side), @ctz(move.dest));
            result.endgame_score += m * value(piece, tables.endgame.get(move.side), @ctz(move.dest));

            if (move.promotion != null) {
                switch (move.promotion.?) {
                    .knight => result.pieces_phase -= 1,
                    .bishop => result.pieces_phase -= 1,
                    .rook => result.pieces_phase -= 2,
                    .queen => result.pieces_phase -= 4,
                }
            }
        }

        if (move.capture != null) {
            const dest = blk: {
                if (move.en_passant) break :blk if (move.side == .white) move.dest << 8 else move.dest >> 8;
                break :blk move.dest;
            };

            result.opening_score += m * value(move.capture.?, tables.opening.get(move.side.other()), @ctz(dest));
            result.endgame_score += m * value(move.capture.?, tables.opening.get(move.side.other()), @ctz(dest));

            switch (move.capture.?) {
                .knight => result.pieces_phase += 1,
                .bishop => result.pieces_phase += 1,
                .rook => result.pieces_phase += 2,
                .queen => result.pieces_phase += 4,
                else => {},
            }
        }

        if (move.castling != null) {
            switch (move.castling.?) {
                .K => {
                    result.opening_score -= value(.rook, tables.opening.white, @ctz(squares.h1));
                    result.endgame_score -= value(.rook, tables.opening.white, @ctz(squares.h1));
                    result.opening_score += value(.rook, tables.opening.white, @ctz(squares.f1));
                    result.endgame_score += value(.rook, tables.opening.white, @ctz(squares.f1));
                },
                .Q => {
                    result.opening_score -= value(.rook, tables.opening.white, @ctz(squares.a1));
                    result.endgame_score -= value(.rook, tables.opening.white, @ctz(squares.a1));
                    result.opening_score += value(.rook, tables.opening.white, @ctz(squares.d1));
                    result.endgame_score += value(.rook, tables.opening.white, @ctz(squares.d1));
                },
                .k => {
                    result.opening_score -= value(.rook, tables.opening.black, @ctz(squares.h8));
                    result.endgame_score -= value(.rook, tables.opening.black, @ctz(squares.h8));
                    result.opening_score += value(.rook, tables.opening.black, @ctz(squares.f8));
                    result.endgame_score += value(.rook, tables.opening.black, @ctz(squares.f8));
                },
                .q => {
                    result.opening_score -= value(.rook, tables.opening.black, @ctz(squares.a8));
                    result.endgame_score -= value(.rook, tables.opening.black, @ctz(squares.a8));
                    result.opening_score += value(.rook, tables.opening.black, @ctz(squares.d8));
                    result.endgame_score += value(.rook, tables.opening.black, @ctz(squares.d8));
                },
            }
        }

        result.phase = @divTrunc(result.pieces_phase * 256 + 12, 24);

        return result;
    }

    pub inline fn evaluate(self: Evaluator, board: *chess.Board) i64 {
        var score: i64 = self.opening_score * (256 - self.phase) + self.endgame_score * self.phase;
        score = mul(self.side) * @divTrunc(score, 256);

        var child = board.copyAndMake(chess.Move.nullMove());
        score += 5 * @as(i64, @popCount(movegen.space(board)));
        score -= 5 * @as(i64, @popCount(movegen.space(&child)));

        return score;
    }
};
