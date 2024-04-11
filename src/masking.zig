//! This module contains BitIterator and masks for row, column, ascending and descending diagonal for each square index.

const squares = @import("squares.zig");

pub const full: u64 = 0xffffffffffffffff;

/// An iterator to extract lowest bit from a mask.
pub const BitIterator = struct {
    mask: u64 = 0,

    pub fn init(mask: u64) BitIterator {
        return BitIterator{ .mask = mask };
    }

    /// Extract the lowest bit if there is one remaining.
    pub inline fn next(self: *BitIterator) ?u64 {
        if (self.mask == 0) return null;
        const lowest_bit: u64 = @as(u64, 1) << @intCast(@ctz(self.mask));
        self.mask -= lowest_bit;
        return lowest_bit;
    }
};

pub const masks = struct {
    /// Array of row masks for each squares.
    pub const rows = blk: {
        var result: [64]u64 = undefined;
        for (0..64) |i| result[i] = squares.row_8 << @intCast(i & 56);
        break :blk result;
    };

    /// Array of column masks for each squares.
    pub const cols = blk: {
        var result: [64]u64 = undefined;
        for (0..64) |i| result[i] = squares.col_a << @intCast(i & 7);
        break :blk result;
    };

    /// Array of ascending diagonal masks for each squares.
    pub const ascs = blk: {
        var result: [64]u64 = undefined;
        for (0..64) |i| {
            var asc: u64 = 1 << @intCast(i);
            for (0..i & 7) |_| asc |= asc << 7;
            for (i & 7..7) |_| asc |= asc >> 7;
            result[i] = asc;
        }
        break :blk result;
    };

    /// Array of descending diagonal masks for each squares.
    pub const descs = blk: {
        var result: [64]u64 = undefined;
        for (0..64) |i| {
            var desc: u64 = 1 << @intCast(i);
            for (0..i & 7) |_| desc |= desc >> 9;
            for (i & 7..7) |_| desc |= desc << 9;
            result[i] = desc;
        }
        break :blk result;
    };
};
