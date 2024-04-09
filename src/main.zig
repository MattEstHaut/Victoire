const std = @import("std");
const victoire = @import("victoire.zig");
const io = @import("io.zig");

pub fn main() !void {
    var args = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args.deinit();

    _ = args.skip();
    const fen = args.next() orelse return error.no_fen;
    const depth = try std.fmt.parseInt(u32, args.next() orelse return error.no_depth, 10);
    const board = try io.parsing.board(fen);

    var engine = victoire.Engine.init();
    defer engine.deinit();

    const t0 = std.time.milliTimestamp();
    const result = engine.search(board, depth, null);
    const dt = std.time.milliTimestamp() - t0;
    const mate = result.checkmate();

    std.debug.print("bestmove:  {s}\n", .{io.stringify(result.best_move)});
    std.debug.print("score:     {d}cp\n", .{result.score});
    std.debug.print("depth:     {d}\n", .{result.depth});
    std.debug.print("time:      {d}ms\n", .{dt});
    std.debug.print("nodes:     {d}\n", .{engine.infos.nodes});
    if (mate != null) std.debug.print("mate:      {d}\n", .{mate.?});
}
