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
            .depth = if (self.depth == 0) 0 else self.depth - 1,
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

    pub inline fn append(self: SearchNode, depth: u32) SearchNode {
        var result = self;
        result.depth += depth;
        return result;
    }

    pub inline fn reduce(self: SearchNode, plies: u32) SearchNode {
        var result = self;
        result.depth -= @min(result.depth, plies);
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
    score: i64 = -evaluation.checkmate,
    is_pv: bool = false,

    pub inline fn appendMove(list: *MoveDataList, move: chess.Move) void {
        list.append(.{
            .move = move,
        }) catch unreachable;
    }

    pub fn lessThan(_: void, self: MoveData, other: MoveData) bool {
        if (other.is_pv) return true;
        if (self.is_pv) return false;
        return self.score < other.score;
    }
};

const Table = transposition.TranspositionTable(TranspositionData);

const TranspositionData = struct {
    search_result: SearchResult = SearchResult.raw(0),
    flag: enum { exact, lower, upper } = .exact,

    pub inline fn init(search_result: SearchResult) TranspositionData {
        return .{ .search_result = search_result };
    }
};

/// The Victory Chess Engine.
pub const Engine = struct {
    options: struct {
        quiesce_depth: u32 = 12,
        table_size: u64 = 1_000_000,
        late_move_reduction: bool = true,
    } = .{},

    data: struct {
        move_list: MoveDataList = undefined,
        deadline: ?i64 = null,
        aborted: bool = false,
        table: Table = undefined,
    } = .{},

    infos: struct {} = .{},

    pub fn init() Engine {
        var engine = Engine{};
        engine.data.move_list = MoveDataList.init(std.heap.page_allocator);
        engine.data.table = Table.init(engine.options.table_size, TranspositionData{}) catch unreachable;
        return engine;
    }

    pub fn initWithSize(size: u64) Engine {
        var engine = Engine{};
        engine.options.table_size = size;
        engine.data.move_list = MoveDataList.init(std.heap.page_allocator);
        engine.data.table = Table.init(engine.options.table_size, TranspositionData{}) catch unreachable;
        return engine;
    }

    pub fn deinit(self: *Engine) void {
        self.data.move_list.deinit();
        self.data.table.deinit();
    }

    pub fn search(self: *Engine, board: chess.Board, depth: u32, time: ?i64) SearchResult {
        self.data.aborted = false;
        self.data.deadline = time;

        if (time != null) self.data.deadline.? += std.time.milliTimestamp();

        var result = SearchResult.raw(0);

        for (1..depth + 1) |ply| {
            const ply_result = self.PVS(SearchNode.root(board, @intCast(ply)));
            if (@atomicLoad(bool, &self.data.aborted, .seq_cst)) break;
            result = ply_result;
        }

        return result;
    }

    fn shouldAbort(self: *Engine) bool {
        if (@atomicLoad(bool, &self.data.aborted, .seq_cst)) return true;

        if (self.data.deadline != null) {
            if (self.data.deadline.? <= std.time.milliTimestamp()) {
                @atomicStore(bool, &self.data.aborted, true, .seq_cst);
                return true;
            }
        }

        return false;
    }

    pub fn stop(self: *Engine) void {
        @atomicStore(bool, &self.data.aborted, true, .seq_cst);
    }

    fn PVS(self: *Engine, node: SearchNode) SearchResult {
        if (self.shouldAbort()) return SearchResult.raw(0);
        if (node.depth == 0) return SearchResult.raw(self.quiesce(node.append(self.options.quiesce_depth)));

        const move_list_len = self.data.move_list.items.len;
        var search_result = SearchResult{ .depth = node.depth };
        var mutable_node = node;
        var pv: ?chess.Move = null;
        var record_depth: u32 = 0;

        // Checks transposition table.
        if (node.depth > 1) transpo: {
            const record = self.data.table.get(node.hash) orelse break :transpo;
            record_depth = record.data.search_result.depth;
            if (record_depth >= node.depth) {
                switch (record.data.flag) {
                    .exact => return record.data.search_result,
                    .lower => mutable_node.alpha = @max(node.alpha, record.data.search_result.score),
                    .upper => mutable_node.beta = @min(node.beta, record.data.search_result.score),
                }
                if (mutable_node.alpha >= mutable_node.beta) return record.data.search_result;
            }
            pv = record.data.search_result.best_move;
        }

        // Generates moves.
        const move_count = movegen.generate(node.board, &self.data.move_list, MoveData.appendMove);

        // Detects checkmate and stalemate.
        if (move_count == 0) return switch (movegen.end(&mutable_node.board)) {
            .checkmate => SearchResult.raw(-@as(i64, evaluation.checkmate) + node.ply),
            .stalemate => SearchResult.raw(evaluation.stalemate),
        };

        // Updates move scores for ordering.
        for (move_list_len..self.data.move_list.items.len) |i| {
            var move_data = &self.data.move_list.items[i];

            if (pv != null and pv.?.sameAs(move_data.move)) {
                move_data.is_pv = true;
                continue;
            }

            const hash = hasher.update(node.hash, move_data.move);
            const record = self.data.table.get(hash);
            if (record != null and record.?.data.flag == .exact) {
                const sr = record.?.data.search_result;
                move_data.score = sr.score + sr.depth * 10;
            } else move_data.score = evaluation.move_evaluation.score(move_data.move) - 200;
        }

        // Orders moves.
        std.sort.heap(MoveData, self.data.move_list.items[move_list_len..], {}, MoveData.lessThan);

        // PVS algorithm.
        for (0..move_count) |i| {
            const move_data = self.data.move_list.pop();

            const child_result = blk: {
                const child = mutable_node.next(move_data.move);
                if (i == 0) break :blk self.PVS(child).inv();

                // Late move reduction.
                const lmr: u32 = reduc: {
                    if (!self.options.late_move_reduction) break :reduc 0;
                    if (move_data.move.capture != null) break :reduc 0;
                    if (node.depth < 4) break :reduc 0;

                    const last_depth = node.ply + node.depth - 1;
                    if (last_depth < 8) {
                        if (i < 5) break :reduc 0;
                        break :reduc 1;
                    } else {
                        if (i < 4) break :reduc 0;
                        if (i < 8) break :reduc 1;
                        break :reduc node.depth / 2;
                    }
                };

                const result = self.PVS(child.reduce(lmr).nullWindow()).inv();
                if (mutable_node.alpha < result.score and result.score < mutable_node.beta)
                    break :blk self.PVS(child.reduce(lmr)).inv();
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

        // Saves search result in transposition table.
        if (node.depth >= record_depth) {
            var record = TranspositionData.init(search_result);
            if (search_result.score <= node.alpha) record.flag = .upper;
            if (search_result.score >= mutable_node.beta) record.flag = .lower;
            self.data.table.set(node.hash, record);
        }

        return search_result;
    }

    fn quiesce(self: *Engine, node: SearchNode) i64 {
        if (self.shouldAbort()) return 0;

        const pat = evaluation.board_evaluation.material(node.board);
        if (node.depth == 0) return pat;

        if (pat >= node.beta) return node.beta;

        var mutable_node = node;
        mutable_node.alpha = @max(node.alpha, pat);
        const move_list_len = self.data.move_list.items.len;

        const move_count = movegen.generate(node.board, &self.data.move_list, MoveData.appendMove);

        if (move_count == 0) return switch (movegen.end(&mutable_node.board)) {
            .checkmate => -@as(i64, evaluation.checkmate) + node.ply,
            .stalemate => evaluation.stalemate,
        };

        for (0..move_count) |_| {
            const move_data = self.data.move_list.pop();
            if (move_data.move.capture == null) continue;

            const score = -self.quiesce(mutable_node.next(move_data.move));

            if (score >= mutable_node.beta) {
                self.data.move_list.resize(move_list_len) catch unreachable;
                return mutable_node.beta;
            }

            mutable_node.alpha = @max(mutable_node.alpha, score);
        }

        return mutable_node.alpha;
    }
};
