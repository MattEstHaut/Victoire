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
    opening_bonus: i64 = 0,
    endgame_bonus: i64 = 0,

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
        result.opening_bonus = -self.opening_bonus;
        result.endgame_bonus = -self.endgame_bonus;
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

    pub inline fn evaluate(self: *Evaluator, board: *chess.Board) i64 {
        const child = board.copyAndMake(chess.Move.nullMove());
        const occ = board.white.occupied | board.black.occupied;

        const ally_count_result = movegen.count(board.*);
        const enemy_count_result = movegen.count(child);

        const ally_mobility: i64 = @intCast(ally_count_result.mobility);
        const enemy_mobility: i64 = @intCast(enemy_count_result.mobility);
        const mobility_diff: i64 = ally_mobility - enemy_mobility;

        const ally_space: i64 = @popCount(ally_count_result.space);
        const enemy_space: i64 = @popCount(enemy_count_result.space);
        const space_diff: i64 = ally_space - enemy_space;

        const ally_threat: i64 = @popCount(movegen.lookup.queen(board.allies().king, occ));
        const enemy_threat: i64 = @popCount(movegen.lookup.queen(board.enemies().king, occ));
        const threat_diff = enemy_threat - ally_threat;

        var opening = mul(self.side) * self.opening_score;
        var endgame = mul(self.side) * self.endgame_score;

        self.opening_bonus = mobility_diff * 3;
        self.opening_bonus += space_diff * 2;
        self.opening_bonus += threat_diff * 4;

        self.endgame_bonus = mobility_diff * 2;
        self.endgame_bonus += space_diff * 1;
        self.endgame_bonus += threat_diff * 0;

        opening += self.opening_bonus;
        endgame += self.endgame_bonus;

        const score: i64 = opening * (256 - self.phase) + endgame * self.phase;
        return @divTrunc(score, 256);
    }

    pub inline fn look(self: Evaluator) i64 {
        const opening = mul(self.side) * self.opening_score + self.opening_bonus;
        const endgame = mul(self.side) * self.endgame_score + self.endgame_bonus;
        const score: i64 = opening * (256 - self.phase) + endgame * self.phase;
        return @divTrunc(score, 256);
    }

    pub inline fn capture(self: Evaluator, move: chess.Move) i64 {
        if (move.capture == null) return 0;

        const score: i64 = switch (move.capture.?) {
            .pawn => 100,
            .knight => 300,
            .bishop => 330,
            .rook => 500,
            .queen => 900,
            .king => 0,
        };

        const malus: i64 = switch (move.piece) {
            .pawn => 100,
            .knight => 300,
            .bishop => 330,
            .rook => 500,
            .queen => 900,
            .king => 300,
        };

        return score - @divFloor((256 - self.phase) * malus, 256);
    }
};
