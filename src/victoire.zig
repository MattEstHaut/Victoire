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

const SearchResult = struct {
    best_move: chess.Move = chess.Move.nullMove(),
    score: i64 = -evaluation.checkmate,
    depth: u32 = 0,

    pub inline fn raw(score: i64) SearchResult {
        return .{ .score = score };
    }

    pub inline fn inv(self: SearchResult) SearchResult {
        return .{
            .best_move = self.best_move,
            .score = -self.score,
            .depth = self.depth,
        };
    }
};

const MoveDataList = std.ArrayList(MoveData);

const MoveData = struct {
    move: chess.Move = chess.Move.nullMove(),

    pub inline fn appendMove(list: *MoveDataList, move: chess.Move) void {
        list.append(.{
            .move = move,
        }) catch unreachable;
    }
};

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

    fn PVS(self: *Engine, node: SearchNode) SearchResult {
        if (node.depth == 0) return SearchResult.raw(evaluation.board_evaluation.material(node.board));

        const move_list_len = self.data.move_list.items.len;
        var search_result = SearchResult{ .depth = node.depth };
        var mutable_node = node;

        const move_count = movegen.generate(node.board, &self.data.move_list, MoveData.appendMove);
        for (0..move_count) |i| {
            const move_data = self.data.move_list.pop();

            const child_result = blk: {
                const child = mutable_node.next(move_data.move);
                if (i == 0) break :blk self.PVS(child).inv();
                const result = self.PVS(child.nullWindow()).inv();
                if (mutable_node.alpha < result.score and result.score < mutable_node.beta)
                    break :blk self.PVS(child).inv();
                break :blk result;
            };

            if (child_result.score > mutable_node.alpha) {
                mutable_node.alpha = child_result.score;
                search_result.best_move = move_data.move;
            }

            if (mutable_node.alpha >= mutable_node.beta) {
                self.data.move_list.resize(move_list_len) catch unreachable;
                break;
            }
        }

        search_result.score = mutable_node.alpha;
        return search_result;
    }
};
