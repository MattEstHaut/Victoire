//! This module contains parsing and stringification functions.

const std = @import("std");
const chess = @import("chess.zig");
const squares = @import("squares.zig");

inline fn pieceFromChar(char: u8) ?chess.Piece {
    return switch (char) {
        'p' => .pawn,
        'n' => .knight,
        'b' => .bishop,
        'r' => .rook,
        'q' => .queen,
        'k' => .king,
        else => null,
    };
}

pub const parsing = struct {
    /// Parses a Board from a FEN (Forsyth–Edwards Notation).
    pub fn board(fen: []const u8) !chess.Board {
        var result = chess.Board{};
        var fen_iterator = std.mem.splitScalar(u8, fen, ' ');

        const pieces = fen_iterator.next() orelse return error.unexpected_eof;
        var mask: u64 = 1;
        for (pieces) |char| {
            if (mask == 0) return error.TooManyPieces;

            if (char == '/') continue;
            if (char >= '1' and char <= '8') {
                mask <<= @intCast(char - '0');
                continue;
            }

            var positions = if (char < 97) result.allies() else result.enemies();
            switch (pieceFromChar(char | 32) orelse return error.invalid_piece) {
                .pawn => positions.pawns |= mask,
                .knight => positions.knights |= mask,
                .bishop => positions.bishops |= mask,
                .rook => positions.rooks |= mask,
                .queen => positions.queens |= mask,
                .king => positions.king |= mask,
            }
            positions.occupied |= mask;
            mask <<= 1;
        }
        if (mask != 0) return error.too_few_pieces;

        const color = fen_iterator.next() orelse return error.unexpected_eof;
        if (color.len != 1) return error.invalid_color;
        result.side = switch (color[0]) {
            'w' => chess.Color.white,
            'b' => chess.Color.black,
            else => return error.invalid_color,
        };

        result.castling_rights.K = false;
        result.castling_rights.Q = false;
        result.castling_rights.k = false;
        result.castling_rights.q = false;

        const castling_rights = fen_iterator.next() orelse return error.unexpected_eof;
        if (castling_rights.len > 4) return error.invalid_castling_rights;
        if (!(castling_rights.len == 1 and castling_rights[0] == '-')) {
            for (castling_rights) |char| {
                switch (char) {
                    'K' => result.castling_rights.K = true,
                    'Q' => result.castling_rights.Q = true,
                    'k' => result.castling_rights.k = true,
                    'q' => result.castling_rights.q = true,
                    else => return error.invalid_castling_rights,
                }
            }
        }

        const en_passant = fen_iterator.next() orelse return error.unexpected_eof;
        if (en_passant.len == 2) {
            const file = en_passant[0];
            const rank = en_passant[1];
            if (file < 'a' or file > 'h' or rank < '1' or rank > '8') return error.invalid_en_passant;
            result.en_passant = @as(u64, 1) << @intCast(file - 'a' + ('8' - rank) * 8);
        } else if (!(en_passant.len == 1 and en_passant[0] == '-')) return error.invalid_en_passant;

        return result;
    }

    /// Parses a Move from a UCI (Universal Chess Interface) notation.
    pub fn move(move_str: []const u8) !chess.PartialMove {
        if (move_str.len < 4) return error.move_too_short;
        if (move_str.len > 5) return error.move_too_long;
        if (move_str[0] < 'a' or move_str[0] > 'h') return error.invalid_first_column;
        if (move_str[1] < '1' or move_str[1] > '8') return error.invalid_first_row;
        if (move_str[2] < 'a' or move_str[2] > 'h') return error.invalid_second_column;
        if (move_str[3] < '1' or move_str[3] > '8') return error.invalid_second_row;

        var partial = chess.PartialMove{
            .src = @as(u64, 1) << @intCast(move_str[0] - 'a' + 8 * ('8' - move_str[1])),
            .dest = @as(u64, 1) << @intCast(move_str[2] - 'a' + 8 * ('8' - move_str[3])),
        };

        if (move_str.len == 5) {
            partial.promotion = switch (move_str[4]) {
                'q' => .queen,
                'r' => .rook,
                'b' => .bishop,
                'n' => .knight,
                else => return error.invalid_promotion,
            };
        }

        return partial;
    }
};

pub const MoveStringifier = struct {
    data: [5]u8 = undefined,

    /// Stringifies a Move.
    pub inline fn stringify(self: *MoveStringifier, move: chess.Move) []u8 {
        if (!move.null_move) {
            self.data[0] = 'a' + (@ctz(move.src) & 7);
            self.data[1] = '8' - (@ctz(move.src) >> 3);
            self.data[2] = 'a' + (@ctz(move.dest) & 7);
            self.data[3] = '8' - (@ctz(move.dest) >> 3);

            if (move.promotion != null) {
                self.data[4] = switch (move.promotion.?) {
                    .queen => 'q',
                    .rook => 'r',
                    .bishop => 'b',
                    .knight => 'n',
                };
                return self.data[0..5];
            }
        } else std.mem.copyForwards(u8, &self.data, "null");

        return self.data[0..4];
    }
};
