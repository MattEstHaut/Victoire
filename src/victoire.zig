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

    fn PVS(self: *Engine, node: SearchNode) i64 {
        if (node.depth == 0) return evaluation.board_evaluation.material(node.board);
        const move_list_len = self.data.move_list.items.len;
        var mutable_node = node;

        const move_count = movegen.generate(node.board, &self.data.move_list, appendMove);
        for (0..move_count) |i| {
            const move_data = self.data.move_list.pop();

            const score: i64 = blk: {
                const child = mutable_node.next(move_data.move);
                if (i == 0) break :blk -self.PVS(child);
                const score = -self.PVS(child.nullWindow());
                if (mutable_node.alpha < score and score < mutable_node.beta)
                    break :blk -self.PVS(child);
                break :blk score;
            };

            mutable_node.alpha = @max(mutable_node.alpha, score);
            if (mutable_node.alpha >= mutable_node.beta) {
                self.data.move_list.resize(move_list_len) catch unreachable;
                break;
            }
        }

        return mutable_node.alpha;
    }
};
