//! This module contains move generation related features.

const std = @import("std");
const chess = @import("chess.zig");
const squares = @import("squares.zig");
const masking = @import("masking.zig");

const lookup = struct {
    pub inline fn king(bb: u64) u64 {
        const no_left = bb & ~squares.col_a;
        const no_right = bb & ~squares.col_h;
        var result = bb;
        result |= no_left >> 1;
        result |= no_right << 1;
        result |= result << 8 | result >> 8;
        return result - bb;
    }

    pub inline fn knight(bb: u64) u64 {
        const no_left = bb & ~squares.col_a;
        const no_left_double = no_left & ~squares.col_b;
        const no_right = bb & ~squares.col_h;
        const no_right_double = no_right & ~squares.col_g;
        var result = no_left >> 17;
        result |= no_left_double >> 10;
        result |= no_left_double << 6;
        result |= no_left << 15;
        result |= no_right << 17;
        result |= no_right_double << 10;
        result |= no_right_double >> 6;
        result |= no_right >> 15;
        return result;
    }

    inline fn hyperbolaQuintessence(s: u64, o: u64, m: u64) u64 {
        @setRuntimeSafety(false);
        return (((o & m) - 2 * s) ^ @bitReverse(@bitReverse(o & m) - 2 * @bitReverse(s))) & m;
    }

    pub inline fn bishop(bb: u64, occ: u64) u64 {
        const index = @ctz(bb);
        const ascending = hyperbolaQuintessence(bb, occ, masking.masks.ascs[index]);
        const descending = hyperbolaQuintessence(bb, occ, masking.masks.descs[index]);
        return ascending | descending;
    }

    pub inline fn rook(bb: u64, occ: u64) u64 {
        const index = @ctz(bb);
        const horizontal = hyperbolaQuintessence(bb, occ, masking.masks.rows[index]);
        const vertical = hyperbolaQuintessence(bb, occ, masking.masks.cols[index]);
        return horizontal | vertical;
    }

    pub inline fn queen(bb: u64, occ: u64) u64 {
        return bishop(bb, occ) | rook(bb, occ);
    }

    pub inline fn pawnsForward(bb: u64, occ: u64, side: chess.Color) u64 {
        return switch (side) {
            .white => (bb >> 8) & ~occ,
            .black => (bb << 8) & ~occ,
        };
    }

    pub inline fn pawnsDoubleForward(bb: u64, occ: u64, side: chess.Color) u64 {
        const src = bb & if (side == .white) squares.row_2 else squares.row_7;
        return pawnsForward(pawnsForward(src, occ, side), occ, side);
    }

    pub inline fn pawnCaptures(bb: u64, side: chess.Color) u64 {
        const no_left = bb & ~squares.col_a;
        const no_right = bb & ~squares.col_h;
        return switch (side) {
            .white => (no_left >> 9) | (no_right >> 7),
            .black => (no_left << 7) | (no_right << 9),
        };
    }
};

const PinCheck = struct {
    check: u64 = 0,
    pin_hor: u64 = 0,
    pin_ver: u64 = 0,
    pin_asc: u64 = 0,
    pin_desc: u64 = 0,
    checks: u7 = 0,

    inline fn hyperbolaQuintessenceSimple(s: u64, o: u64, m: u64) u64 {
        @setRuntimeSafety(false);
        return (o & m) ^ ((o & m) - 2 * s) & m;
    }

    inline fn hyperbolaQuintessenceReversed(s: u64, o: u64, m: u64) u64 {
        @setRuntimeSafety(false);
        return (o & m) ^ @bitReverse(@bitReverse(o & m) - 2 * @bitReverse(s)) & m;
    }

    inline fn update(self: *PinCheck, mask: u64, atk: u64, occ: u64, pin: *u64) void {
        if (mask & atk != 0) {
            const blockers = @popCount(mask & occ);
            if (blockers == 1) {
                self.check |= mask;
                self.checks += 1;
            } else if (blockers == 2) {
                pin.* |= mask;
            }
        }
    }

    pub inline fn init(board: chess.Board) PinCheck {
        var mutable_board = board;
        const king = mutable_board.allies().king;
        const ennemies = mutable_board.enemies().*;
        const occupied = board.white.occupied | board.black.occupied;

        var result = PinCheck{};
        result.check = lookup.knight(king) & ennemies.knights;
        result.check |= lookup.pawnCaptures(king, board.side) & ennemies.pawns;
        result.checks = @popCount(result.check);

        const index = @ctz(king);
        const row = masking.masks.rows[index];
        const col = masking.masks.cols[index];
        const asc = masking.masks.ascs[index];
        const desc = masking.masks.descs[index];

        const hv_atks = ennemies.rooks | ennemies.queens;
        const ad_atks = ennemies.bishops | ennemies.queens;

        const top = hyperbolaQuintessenceReversed(king, hv_atks, col);
        const bottom = hyperbolaQuintessenceSimple(king, hv_atks, col);
        const left = hyperbolaQuintessenceReversed(king, hv_atks, row);
        const right = hyperbolaQuintessenceSimple(king, hv_atks, row);

        const top_left = hyperbolaQuintessenceReversed(king, ad_atks, desc);
        const bottom_right = hyperbolaQuintessenceSimple(king, ad_atks, desc);
        const top_right = hyperbolaQuintessenceReversed(king, ad_atks, asc);
        const bottom_left = hyperbolaQuintessenceSimple(king, ad_atks, asc);

        result.update(top, hv_atks, occupied, &result.pin_ver);
        result.update(bottom, hv_atks, occupied, &result.pin_ver);
        result.update(left, hv_atks, occupied, &result.pin_hor);
        result.update(right, hv_atks, occupied, &result.pin_hor);
        result.update(top_left, ad_atks, occupied, &result.pin_desc);
        result.update(bottom_right, ad_atks, occupied, &result.pin_desc);
        result.update(top_right, ad_atks, occupied, &result.pin_asc);
        result.update(bottom_left, ad_atks, occupied, &result.pin_asc);

        if (result.check == 0) result.check = masking.full;
        return result;
    }
};

/// Checks if square is attacked. @popcCount(bb) == 1.
pub inline fn isAttacked(board: chess.Board, bb: u64) bool {
    var mutable_board = board;
    const atks = mutable_board.enemies().*;
    const blockers = (board.white.occupied | board.black.occupied) & ~mutable_board.allies().king;

    if (lookup.king(atks.king) & bb != 0) return true;
    if (lookup.knight(atks.knights) & bb != 0) return true;
    if (lookup.pawnCaptures(atks.pawns, board.side.other()) & bb != 0) return true;

    const hv_atks = atks.rooks | atks.queens;
    const ad_atks = atks.bishops | atks.queens;
    if (lookup.rook(bb, blockers) & hv_atks != 0) return true;
    if (lookup.bishop(bb, blockers) & ad_atks != 0) return true;

    return false;
}

const castling_right = struct {
    pub fn K(board: chess.Board) bool {
        if (!board.castling_rights.K) return false;
        if ((board.white.occupied | board.black.occupied) & (0b11 << 61) != 0) return false;
        if (isAttacked(board, squares.e1)) return false;
        if (isAttacked(board, squares.f1)) return false;
        if (isAttacked(board, squares.g1)) return false;
        return true;
    }

    pub fn Q(board: chess.Board) bool {
        if (!board.castling_rights.Q) return false;
        if ((board.white.occupied | board.black.occupied) & (0b111 << 57) != 0) return false;
        if (isAttacked(board, squares.e1)) return false;
        if (isAttacked(board, squares.d1)) return false;
        if (isAttacked(board, squares.c1)) return false;
        return true;
    }

    pub fn k(board: chess.Board) bool {
        if (!board.castling_rights.k) return false;
        if ((board.white.occupied | board.black.occupied) & (0b11 << 5) != 0) return false;
        if (isAttacked(board, squares.e8)) return false;
        if (isAttacked(board, squares.f8)) return false;
        if (isAttacked(board, squares.g8)) return false;
        return true;
    }

    pub fn q(board: chess.Board) bool {
        if (!board.castling_rights.q) return false;
        if ((board.white.occupied | board.black.occupied) & (0b111 << 1) != 0) return false;
        if (isAttacked(board, squares.e8)) return false;
        if (isAttacked(board, squares.d8)) return false;
        if (isAttacked(board, squares.c8)) return false;
        return true;
    }
};

/// Generates moves and call handler at each move found.
pub fn generate(board: chess.Board, context: anytype, handler: fn (@TypeOf(context), chess.Move) callconv(.Inline) void) u32 {
    var nodes: u32 = 0;
    var mutable_board = board;

    const occupied = board.white.occupied | board.black.occupied;
    const positions = mutable_board.allies().*;
    const empty_or_enemy = (~occupied | mutable_board.enemies().occupied) & ~mutable_board.enemies().king;
    const pin_and_check = PinCheck.init(board);

    const prom_row = switch (board.side) {
        .white => squares.row_8,
        .black => squares.row_1,
    };

    {
        var move = chess.Move{ .src = positions.king, .piece = .king, .side = board.side };
        const atks = lookup.king(move.src) & empty_or_enemy;
        var dest_iter = masking.BitIterator.init(atks);
        while (dest_iter.next()) |dest| {
            if (!isAttacked(board, dest)) {
                move.dest = dest;
                move.capture = mutable_board.enemies().collision(dest);
                handler(context, move);
                nodes += 1;
            }
        }
    }

    if (pin_and_check.checks > 1) return nodes;

    const pin_hv = pin_and_check.pin_hor | pin_and_check.pin_ver;
    const pin_ad = pin_and_check.pin_asc | pin_and_check.pin_desc;

    {
        var move = chess.Move{ .piece = .knight, .side = board.side };
        var src_iter = masking.BitIterator.init(positions.knights & ~(pin_hv | pin_ad));
        while (src_iter.next()) |src| {
            const atks = lookup.knight(src) & empty_or_enemy & pin_and_check.check;
            var dest_iter = masking.BitIterator.init(atks);
            while (dest_iter.next()) |dest| {
                move.src = src;
                move.dest = dest;
                move.capture = mutable_board.enemies().collision(dest);
                handler(context, move);
                nodes += 1;
            }
        }
    }

    {
        var move = chess.Move{ .piece = .bishop, .side = board.side };
        var src_iter = masking.BitIterator.init(positions.bishops & ~pin_hv);
        while (src_iter.next()) |src| {
            var pin = masking.full;
            if (pin_and_check.pin_asc & src > 0) {
                pin = pin_and_check.pin_asc;
            } else if (pin_and_check.pin_desc & src > 0) {
                pin = pin_and_check.pin_desc;
            }

            const atks = lookup.bishop(src, occupied) & empty_or_enemy & pin_and_check.check & pin;
            var dest_iter = masking.BitIterator.init(atks);
            while (dest_iter.next()) |dest| {
                move.src = src;
                move.dest = dest;
                move.capture = mutable_board.enemies().collision(dest);
                handler(context, move);
                nodes += 1;
            }
        }
    }

    {
        var move = chess.Move{ .piece = .rook, .side = board.side };
        var src_iter = masking.BitIterator.init(positions.rooks & ~pin_ad);
        while (src_iter.next()) |src| {
            var pin = masking.full;
            if (pin_and_check.pin_hor & src > 0) {
                pin = pin_and_check.pin_hor;
            } else if (pin_and_check.pin_ver & src > 0) {
                pin = pin_and_check.pin_ver;
            }

            const atks = lookup.rook(src, occupied) & empty_or_enemy & pin_and_check.check & pin;
            var dest_iter = masking.BitIterator.init(atks);
            while (dest_iter.next()) |dest| {
                move.src = src;
                move.dest = dest;
                move.capture = mutable_board.enemies().collision(dest);
                handler(context, move);
                nodes += 1;
            }
        }
    }

    {
        var move = chess.Move{ .piece = .queen, .side = board.side };
        var src_iter = masking.BitIterator.init(positions.queens);
        while (src_iter.next()) |src| {
            var pin = masking.full;
            if (pin_and_check.pin_asc & src > 0) {
                pin = pin_and_check.pin_asc;
            } else if (pin_and_check.pin_desc & src > 0) {
                pin = pin_and_check.pin_desc;
            } else if (pin_and_check.pin_hor & src > 0) {
                pin = pin_and_check.pin_hor;
            } else if (pin_and_check.pin_ver & src > 0) {
                pin = pin_and_check.pin_ver;
            }

            const atks = lookup.queen(src, occupied) & empty_or_enemy & pin_and_check.check & pin;
            var dest_iter = masking.BitIterator.init(atks);
            while (dest_iter.next()) |dest| {
                move.src = src;
                move.dest = dest;
                move.capture = mutable_board.enemies().collision(dest);
                handler(context, move);
                nodes += 1;
            }
        }
    }

    {
        var move = chess.Move{ .piece = .pawn, .side = board.side };
        var src_iter = masking.BitIterator.init(positions.pawns & ~(pin_ad | pin_and_check.pin_hor));
        while (src_iter.next()) |src| {
            move.dest = lookup.pawnsForward(src, occupied, board.side) & pin_and_check.check;
            if (move.dest == 0) continue;
            move.src = src;

            if (move.dest & prom_row > 0) {
                move.promotion = .knight;
                handler(context, move);
                move.promotion = .bishop;
                handler(context, move);
                move.promotion = .rook;
                handler(context, move);
                move.promotion = .queen;
                handler(context, move);
                nodes += 4;
            } else {
                move.promotion = null;
                handler(context, move);
                nodes += 1;
            }
        }
    }

    {
        var move = chess.Move{ .piece = .pawn, .side = board.side };
        var src_iter = masking.BitIterator.init(positions.pawns & ~(pin_ad | pin_and_check.pin_hor));
        while (src_iter.next()) |src| {
            move.dest = lookup.pawnsDoubleForward(src, occupied, board.side) & pin_and_check.check;
            if (move.dest == 0) continue;
            move.src = src;
            handler(context, move);
            nodes += 1;
        }
    }

    {
        var move = chess.Move{ .piece = .pawn, .side = board.side };
        var src_iter = masking.BitIterator.init(positions.pawns & ~pin_hv);
        while (src_iter.next()) |src| {
            var pin = masking.full;
            if (pin_and_check.pin_asc & src > 0) {
                pin = pin_and_check.pin_asc;
            } else if (pin_and_check.pin_desc & src > 0) {
                pin = pin_and_check.pin_desc;
            }

            move.src = src;

            const atks_mask = pin_and_check.check & pin & mutable_board.enemies().occupied & ~mutable_board.enemies().king;
            const atks = lookup.pawnCaptures(src, board.side) & atks_mask;
            var dest_iter = masking.BitIterator.init(atks);
            while (dest_iter.next()) |dest| {
                move.dest = dest;
                move.capture = mutable_board.enemies().collision(dest);

                if (dest & prom_row > 0) {
                    move.promotion = .knight;
                    handler(context, move);
                    move.promotion = .bishop;
                    handler(context, move);
                    move.promotion = .rook;
                    handler(context, move);
                    move.promotion = .queen;
                    handler(context, move);
                    nodes += 4;
                } else {
                    move.promotion = null;
                    handler(context, move);
                    nodes += 1;
                }
            }
        }
    }

    {
        var move = chess.Move{
            .piece = .pawn,
            .dest = board.en_passant,
            .capture = .pawn,
            .en_passant = true,
            .side = board.side,
        };

        const en_passant_check = lookup.pawnsForward(pin_and_check.check, 0, board.side) & move.dest | pin_and_check.check;
        const mask = lookup.pawnCaptures(move.dest & en_passant_check, board.side.other());
        var src_iter = masking.BitIterator.init(positions.pawns & ~pin_hv & mask);
        while (src_iter.next()) |src| {
            move.src = src;
            var board_test = board.copyAndMake(move);
            board_test.side = move.side;
            if (!isAttacked(board_test, positions.king)) {
                handler(context, move);
                nodes += 1;
            }
        }
    }

    {
        var move = chess.Move{ .piece = .king, .side = board.side, .src = positions.king };
        switch (board.side) {
            .white => {
                if (castling_right.K(board)) {
                    move.dest = squares.g1;
                    move.castling = .K;
                    handler(context, move);
                    nodes += 1;
                }
                if (castling_right.Q(board)) {
                    move.dest = squares.c1;
                    move.castling = .Q;
                    handler(context, move);
                    nodes += 1;
                }
            },
            .black => {
                if (castling_right.k(board)) {
                    move.dest = squares.g8;
                    move.castling = .k;
                    handler(context, move);
                    nodes += 1;
                }
                if (castling_right.q(board)) {
                    move.dest = squares.c8;
                    move.castling = .q;
                    handler(context, move);
                    nodes += 1;
                }
            },
        }
    }

    return nodes;
}

pub const MoveList = std.ArrayList(chess.Move);

/// Adds the Move to the list. Intended to be used with generate().
pub inline fn append(list: *MoveList, move: chess.Move) void {
    list.append(move);
}
