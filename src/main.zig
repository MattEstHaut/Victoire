const std = @import("std");
const blazing = @import("blazing/src/blazing.zig");

pub fn main() !void {
    const board = try blazing.io.parse("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -");
    std.debug.print("Board: \n{s}\n", .{blazing.io.stringify(board).string});
}
