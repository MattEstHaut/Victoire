//! This module contains perft function.

const std = @import("std");
const chess = @import("chess.zig");
const movegen = @import("movegen.zig");
const io = @import("io.zig");

inline fn perftHandler(context: *std.ArrayList(chess.Move), move: chess.Move) void {
    context.append(move) catch unreachable;
}

fn perftCallback(board: chess.Board, depth: u32, list: *std.ArrayList(chess.Move)) !u32 {
    if (depth == 0) return 1;
    const move_count = movegen.generate(board, list, perftHandler);
    if (depth == 1) {
        try list.resize(list.items.len - move_count);
        return move_count;
    }

    var nodes: u32 = 0;

    for (0..move_count) |_| {
        const next = board.copyAndMake(list.pop());
        nodes += try perftCallback(next, depth - 1, list);
    }

    return nodes;
}

/// Counts leaf nodes and displays debugging information.
pub fn perft(board: chess.Board, depth: u32) !u32 {
    if (depth == 0) return 1;

    const allocator = std.heap.page_allocator;
    var list = std.ArrayList(chess.Move).init(allocator);
    defer list.deinit();

    var total_nodes: u32 = 0;
    const moves_count = movegen.generate(board, &list, perftHandler);

    for (0..moves_count) |_| {
        const move = list.pop();
        const nodes = try perftCallback(board.copyAndMake(move), depth - 1, &list);
        std.debug.print("{s}: {d}\n", .{ io.stringify(move), nodes });
        total_nodes += nodes;
    }

    std.debug.print("total nodes: {d}\n", .{total_nodes});

    return total_nodes;
}
