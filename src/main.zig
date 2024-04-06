const std = @import("std");
const perft = @import("perft.zig");
const io = @import("io.zig");

pub fn main() !void {
    var args = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args.deinit();

    _ = args.skip();
    const fen = args.next() orelse return error.no_fen;
    const depth = try std.fmt.parseInt(u32, args.next() orelse return error.no_depth, 10);

    const board = try io.parsing.board(fen);
    _ = try perft.perft(board, depth);
}
