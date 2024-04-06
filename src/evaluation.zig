//! Contains heuristic evaluation functions.

const chess = @import("chess.zig");

/// Contains evaluation functions for Board.
pub const board_evaluation = struct {
    pub inline fn material(board: chess.Board) i64 {
        var score: i64 = 0;

        score += @as(i64, @popCount(board.white.pawns)) * 100;
        score -= @as(i64, @popCount(board.black.pawns)) * 100;
        score += @as(i64, @popCount(board.white.knights)) * 320;
        score -= @as(i64, @popCount(board.black.knights)) * 320;
        score += @as(i64, @popCount(board.white.bishops)) * 330;
        score -= @as(i64, @popCount(board.black.bishops)) * 330;
        score += @as(i64, @popCount(board.white.rooks)) * 500;
        score -= @as(i64, @popCount(board.black.rooks)) * 500;
        score += @as(i64, @popCount(board.white.queens)) * 900;
        score -= @as(i64, @popCount(board.black.queens)) * 900;

        return if (board.side == .white) score else -score;
    }
};

/// Contains evaluation functions for Move.
pub const move_evaluation = struct {
    pub inline fn score(move: chess.Move) i64 {
        if (move.promotion != null) return switch (move.promotion.?) {
            .queen => 800,
            .rook => 400,
            .bishop => 230,
            .knight => 220,
        };

        if (move.capture != null) {
            const capture_score: i64 = switch (move.capture.?) {
                .pawn => 100,
                .knight => 320,
                .bishop => 330,
                .rook => 500,
                .queen => 900,
                .king => 20_000,
            };

            const penalty: i64 = switch (move.piece) {
                .pawn => 0,
                .knight => 30,
                .bishop => 30,
                .rook => 50,
                .queen => 90,
                .king => 100,
            };

            return capture_score - penalty;
        }

        return 0;
    }
};
