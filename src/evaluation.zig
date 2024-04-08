//! Contains heuristic evaluation functions.

const chess = @import("chess.zig");
const squares = @import("squares.zig");
const tables = @import("pst.zig");

pub const checkmate = 1_000_000;
pub const stalemate = 0;

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
    material_score: i64 = 0,
    pieces_phase: i64 = 24,
    phase: i64 = 0,
    side: chess.Color = .white,
    mode: enum { tapered, material } = .tapered,

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

        evaluator.material_score += @as(i64, @popCount(board.white.pawns)) * 100;
        evaluator.material_score -= @as(i64, @popCount(board.black.pawns)) * 100;
        evaluator.material_score += @as(i64, @popCount(board.white.knights)) * 320;
        evaluator.material_score -= @as(i64, @popCount(board.black.knights)) * 320;
        evaluator.material_score += @as(i64, @popCount(board.white.bishops)) * 330;
        evaluator.material_score -= @as(i64, @popCount(board.black.bishops)) * 330;
        evaluator.material_score += @as(i64, @popCount(board.white.rooks)) * 500;
        evaluator.material_score -= @as(i64, @popCount(board.black.rooks)) * 500;
        evaluator.material_score += @as(i64, @popCount(board.white.queens)) * 900;
        evaluator.material_score -= @as(i64, @popCount(board.black.queens)) * 900;

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

                switch (move.promotion.?) {
                    .knight => result.material_score += m * 220,
                    .bishop => result.material_score += m * 230,
                    .rook => result.material_score += m * 400,
                    .queen => result.material_score += m * 800,
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

            switch (move.capture.?) {
                .pawn => result.material_score += m * 100,
                .knight => result.material_score += m * 320,
                .bishop => result.material_score += m * 330,
                .rook => result.material_score += m * 500,
                .queen => result.material_score += m * 900,
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

    pub inline fn evaluate(self: Evaluator) i64 {
        const m = mul(self.side);
        return switch (self.mode) {
            .tapered => m * @divTrunc(self.opening_score * (256 - self.phase) + self.endgame_score * self.phase, 256),
            .material => m * self.material_score,
        };
    }
};
