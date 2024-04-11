const std = @import("std");
const chess = @import("chess.zig");
const io = @import("io.zig");
const movegen = @import("movegen.zig");
const victoire = @import("victoire.zig");

var buffer = std.mem.zeroes([1 << 20]u8);
var fba = std.heap.FixedBufferAllocator.init(&buffer);
const allocator = fba.allocator();

const Move = i32;

export fn allocate(len: usize) ?[*]u8 {
    return if (allocator.alloc(u8, len)) |slice|
        slice.ptr
    else |_|
        null;
}

export fn free(ptr: [*]u8, len: usize) void {
    allocator.free(ptr[0..len]);
}

export fn parse(fen: [*]u8) ?*chess.Board {
    var len: usize = 0;
    while (fen[len] != 0) len += 1;

    if (allocator.create(chess.Board)) |ptr| {
        if (io.parsing.board(fen[0..len])) |board| {
            ptr.* = board;
            return ptr;
        } else |_| {}
    } else |_| {}

    return null;
}

export fn destroyBoard(board: *chess.Board) void {
    allocator.destroy(board);
}

export fn generate(board: *chess.Board) ?*std.ArrayList(Move) {
    const list = allocator.create(std.ArrayList(Move)) catch return null;
    list.* = std.ArrayList(Move).init(allocator);
    _ = movegen.generate(board.*, list, handler);
    return list;
}

export fn pop(list: *std.ArrayList(Move)) i32 {
    return list.popOrNull() orelse blk: {
        list.deinit();
        allocator.destroy(list);
        break :blk 64 * 64 * 8 * 5;
    };
}

export fn make(board: *chess.Board, move: Move) ?*chess.Board {
    var decoded_move = chess.PartialMove{};
    decoded_move.src = @as(u64, 1) << @intCast(move & 0b111111);
    decoded_move.dest = @as(u64, 1) << @intCast(move >> 6 & 0b111111);
    decoded_move.promotion = switch (move >> 12) {
        1 => .knight,
        2 => .bishop,
        3 => .rook,
        4 => .queen,
        else => null,
    };

    const full_move = board.completeMove(decoded_move) catch return null;
    board.make(full_move);
    return board;
}

export fn createEngine(size: usize) ?*victoire.Engine {
    const engine = allocator.create(victoire.Engine) catch return null;
    engine.* = victoire.Engine.initWithSize(size);
    return engine;
}

export fn destroyEngine(engine: *victoire.Engine) void {
    engine.deinit();
    allocator.destroy(engine);
}

export fn search(engine: *victoire.Engine, board: *chess.Board, depth: i32) ?*victoire.SearchResult {
    const result = allocator.create(victoire.SearchResult) catch return null;
    result.* = engine.search(board.*, @intCast(depth));
    return result;
}

export fn destroySearchResult(result: *victoire.SearchResult) void {
    allocator.destroy(result);
}

export fn getBestMove(result: *victoire.SearchResult) i32 {
    return encode(.{
        .src = result.best_move.src,
        .dest = result.best_move.dest,
        .promotion = result.best_move.promotion,
    });
}

fn encode(move: chess.Move) Move {
    var encoded_move: Move = if (move.promotion) |promotion| switch (promotion) {
        .knight => 1,
        .bishop => 2,
        .rook => 3,
        .queen => 4,
    } else 0;

    encoded_move *= 64 * 64;
    encoded_move += @as(i32, @ctz(move.dest)) * 64 + @as(i32, @ctz(move.src));
    return encoded_move;
}

inline fn handler(list: *std.ArrayList(Move), move: chess.Move) void {
    list.append(encode(move)) catch {};
}
