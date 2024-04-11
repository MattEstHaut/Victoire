//! This module contains TranspositionTable and ZobristHasher structs.

const chess = @import("chess.zig");
const squares = @import("squares.zig");
const std = @import("std");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

fn TranspositionRecord(comptime T: type) type {
    return struct {
        hash: u64 = 0,
        data: T = undefined,
        mutex: std.Thread.Mutex = std.Thread.Mutex{},
    };
}

/// Transposition table for T.
pub fn TranspositionTable(comptime T: type) type {
    return struct {
        data: std.ArrayList(TranspositionRecord(T)),
        size: usize,

        pub fn init(size: usize, default_value: T) !TranspositionTable(T) {
            var table = TranspositionTable(T){
                .data = std.ArrayList(TranspositionRecord(T)).init(allocator),
                .size = size,
            };
            for (0..size) |_| try table.data.append(TranspositionRecord(T){ .data = default_value });
            return table;
        }

        pub fn deinit(self: *TranspositionTable(T)) void {
            self.data.deinit();
        }

        /// Gets the record if the hash has been found.
        pub inline fn get(self: *const TranspositionTable(T), hash: u64) ?T {
            const index: usize = @intCast(hash % self.size);
            self.data.items[index].mutex.lock();
            defer self.data.items[index].mutex.unlock();
            const record = self.data.items[index];
            if (record.hash == hash) return record.data;
            return null;
        }

        /// Overwrite the record if there is already one.
        pub inline fn set(self: *TranspositionTable(T), hash: u64, data: T) void {
            const index: usize = @intCast(hash % self.size);
            self.data.items[index].mutex.lock();
            defer self.data.items[index].mutex.unlock();
            self.data.items[index].hash = hash;
            self.data.items[index].data = data;
        }
    };
}

fn m2u64(mask: u64) usize {
    return @intCast(@ctz(mask));
}

pub const ZobristHasher = struct {
    numbers: [12 * 64]u64 = undefined,
    black_to_move: u64 = undefined,

    pub fn init() ZobristHasher {
        @setEvalBranchQuota(12 * 64 * 16);
        var hasher = ZobristHasher{};
        var rng = std.rand.DefaultPrng.init(0);
        for (0..12 * 64) |i| hasher.numbers[i] = rng.next();
        hasher.black_to_move = rng.next();
        return hasher;
    }

    pub inline fn calculate(self: ZobristHasher, board: chess.Board) u64 {
        var hash: u64 = if (board.side == .black) self.black_to_move else 0;

        for (0..64) |i| {
            const mask = @as(u64, 1) << @as(u6, @intCast(i));
            if (mask & board.white.pawns > 0) hash ^= self.numbers[i * 12 + 0];
            if (mask & board.white.knights > 0) hash ^= self.numbers[i * 12 + 1];
            if (mask & board.white.bishops > 0) hash ^= self.numbers[i * 12 + 2];
            if (mask & board.white.rooks > 0) hash ^= self.numbers[i * 12 + 3];
            if (mask & board.white.queens > 0) hash ^= self.numbers[i * 12 + 4];
            if (mask & board.white.king > 0) hash ^= self.numbers[i * 12 + 5];
            if (mask & board.black.pawns > 0) hash ^= self.numbers[i * 12 + 6];
            if (mask & board.black.knights > 0) hash ^= self.numbers[i * 12 + 7];
            if (mask & board.black.bishops > 0) hash ^= self.numbers[i * 12 + 8];
            if (mask & board.black.rooks > 0) hash ^= self.numbers[i * 12 + 9];
            if (mask & board.black.queens > 0) hash ^= self.numbers[i * 12 + 10];
            if (mask & board.black.king > 0) hash ^= self.numbers[i * 12 + 11];
        }

        return hash;
    }

    pub inline fn update(self: ZobristHasher, hash: u64, move: chess.Move) u64 {
        var diff = self.black_to_move;
        if (move.null_move) return hash ^ diff;

        if (move.castling != null) {
            switch (move.castling.?) {
                .K => {
                    diff ^= self.numbers[m2u64(squares.e1) * 12 + 5];
                    diff ^= self.numbers[m2u64(squares.g1) * 12 + 5];
                    diff ^= self.numbers[m2u64(squares.h1) * 12 + 3];
                    diff ^= self.numbers[m2u64(squares.f1) * 12 + 3];
                },
                .Q => {
                    diff ^= self.numbers[m2u64(squares.e1) * 12 + 5];
                    diff ^= self.numbers[m2u64(squares.c1) * 12 + 5];
                    diff ^= self.numbers[m2u64(squares.a1) * 12 + 3];
                    diff ^= self.numbers[m2u64(squares.d1) * 12 + 3];
                },
                .k => {
                    diff ^= self.numbers[m2u64(squares.e8) * 12 + 11];
                    diff ^= self.numbers[m2u64(squares.g8) * 12 + 11];
                    diff ^= self.numbers[m2u64(squares.h8) * 12 + 9];
                    diff ^= self.numbers[m2u64(squares.f8) * 12 + 9];
                },
                .q => {
                    diff ^= self.numbers[m2u64(squares.e8) * 12 + 11];
                    diff ^= self.numbers[m2u64(squares.c8) * 12 + 11];
                    diff ^= self.numbers[m2u64(squares.a8) * 12 + 9];
                    diff ^= self.numbers[m2u64(squares.d8) * 12 + 9];
                },
            }
        } else {
            var ally_index: usize = switch (move.piece) {
                chess.Piece.pawn => 0,
                chess.Piece.knight => 1,
                chess.Piece.bishop => 2,
                chess.Piece.rook => 3,
                chess.Piece.queen => 4,
                chess.Piece.king => 5,
            };
            if (move.side == .black) ally_index += 6;

            diff ^= self.numbers[m2u64(move.src) * 12 + ally_index];

            if (move.promotion == null) {
                diff ^= self.numbers[m2u64(move.dest) * 12 + ally_index];
            } else {
                var promotion_index: usize = switch (move.promotion.?) {
                    .knight => 1,
                    .bishop => 2,
                    .rook => 3,
                    .queen => 4,
                };
                if (move.side == .black) promotion_index += 6;
                diff ^= self.numbers[m2u64(move.dest) * 12 + promotion_index];
            }

            if (move.capture != null) {
                if (move.en_passant) {
                    const enemy_index: usize = if (move.side == .white) 6 else 0;
                    const dest = if (move.side == .white) move.dest << 8 else move.dest >> 8;
                    diff ^= self.numbers[m2u64(dest) * 12 + enemy_index];
                } else {
                    var enemy_index: usize = switch (move.piece) {
                        .pawn => 0,
                        .knight => 1,
                        .bishop => 2,
                        .rook => 3,
                        .queen => 4,
                        .king => 5,
                    };
                    if (move.side == .white) enemy_index += 6;
                    diff ^= self.numbers[m2u64(move.dest) * 12 + enemy_index];
                }
            }
        }

        return hash ^ diff;
    }
};
