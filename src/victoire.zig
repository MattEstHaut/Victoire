//! Contains the chess engine, search functions, and related functionalities.

const std = @import("std");
const chess = @import("chess.zig");
const movegen = @import("movegen.zig");
const transposition = @import("transposition.zig");
const evaluation = @import("evaluation.zig");

const hasher = transposition.ZobristHasher.init();

const SearchNode = struct {
    board: chess.Board,
    depth: u32,
    ply: u32,
    alpha: i64,
    beta: i64,
    hash: u64,

    pub inline fn root(board: chess.Board, depth: u32) SearchNode {
        return .{
            .board = board,
            .depth = depth,
            .ply = 0,
            .alpha = -evaluation.checkmate,
            .beta = evaluation.checkmate,
            .hash = hasher.calculate(board),
        };
    }

    pub inline fn next(self: SearchNode, move: chess.Move) SearchNode {
        return .{
            .board = self.board.copyAndMake(move),
            .depth = self.depth - 1,
            .ply = self.ply + 1,
            .alpha = -self.beta,
            .beta = -self.alpha,
            .hash = hasher.update(self.hash, move),
        };
    }

    pub inline fn nullWindow(self: SearchNode) SearchNode {
        var result = self;
        result.alpha = self.beta - 1;
        return result;
    }
};

const MoveDataList = std.ArrayList(MoveData);

const MoveData = struct {
    move: chess.Move = chess.Move.nullMove(),
};

inline fn appendMove(list: *MoveDataList, move: chess.Move) void {
    list.append(.{
        .move = move,
    }) catch unreachable;
}

/// The Victory Chess Engine.
pub const Engine = struct {
    options: struct {} = .{},
    data: struct {
        move_list: MoveDataList = undefined,
    } = .{},
    infos: struct {} = .{},

    pub fn init() Engine {
        return .{ .data = .{ .move_list = MoveDataList.init(std.heap.page_allocator) } };
    }

    pub fn deinit(self: *Engine) void {
        self.data.move_list.deinit();
    }
};
