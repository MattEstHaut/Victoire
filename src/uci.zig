//! This module contains the UCI engine.

const std = @import("std");
const io = @import("io.zig");
const chess = @import("chess.zig");
const victoire = @import("victoire.zig");
const perft = @import("perft.zig");

const EngineOptions = struct {
    depth: u32 = 50,
    time: ?i64 = null,
    table_size: u64 = 64,
    ponder: bool = false,
    time_control: bool = true,
};

const default_options = EngineOptions{};

pub const Engine = struct {
    options: EngineOptions = .{},

    data: struct {
        board: chess.Board = chess.Board.empty(),
        engine: victoire.Engine = .{},
        search_thread: ?std.Thread = null,
        ponder_thread: ?std.Thread = null,
        is_init: bool = false,
    } = .{},

    pub fn run(self: *Engine) !void {
        const stdin = std.io.getStdIn().reader();
        const stdout = std.io.getStdOut().writer();
        const record_size = @sizeOf(@TypeOf(self.data.engine.data.table.data.items[0]));

        while (true) {
            var input = std.ArrayList(u8).init(std.heap.page_allocator);
            stdin.readUntilDelimiterArrayList(&input, '\n', 5_000) catch continue;
            defer input.deinit();

            var args = std.mem.splitScalar(u8, input.items, ' ');

            {
                var arg = args.next() orelse continue;
                if (std.mem.eql(u8, arg, "uci")) {
                    try stdout.print("id name Victoire\n", .{});
                    try stdout.print("id author Delucchi Matteo\n", .{});

                    try stdout.print(
                        "option name Hash type spin default {d} min 0 max 8192\n",
                        .{default_options.table_size},
                    );

                    try stdout.print(
                        "option name Ponder type check default {any}\n",
                        .{default_options.ponder},
                    );

                    try stdout.print(
                        "option name TimeControl type check default {any}\n",
                        .{default_options.time_control},
                    );

                    try stdout.print("uciok\n", .{});
                    continue;
                }

                if (std.mem.eql(u8, arg, "ucinewgame")) {
                    const size = self.options.table_size * 1048576 / record_size;
                    self.data.engine = victoire.Engine.initWithSize(size);
                    self.data.is_init = true;
                    continue;
                }

                if (std.mem.eql(u8, arg, "isready")) {
                    try stdout.print("readyok\n", .{});
                    continue;
                }

                if (std.mem.eql(u8, arg, "position")) {
                    arg = args.next() orelse continue;
                    if (std.mem.eql(u8, arg, "startpos")) {
                        self.data.board = try io.parsing.board("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
                    } else if (std.mem.eql(u8, arg, "fen")) {
                        arg = args.rest();
                        self.data.board = io.parsing.board(arg) catch continue;
                    } else continue;

                    while (args.next()) |a| if (std.mem.eql(u8, a, "moves")) break;

                    while (args.next()) |arg_move| {
                        const partial_move = try io.parsing.move(arg_move);
                        const move = try self.data.board.completeMove(partial_move);
                        self.data.board.make(move);
                    }

                    continue;
                }

                if (std.mem.eql(u8, arg, "stop")) {
                    self.stop();
                    continue;
                }

                if (std.mem.eql(u8, arg, "go")) {
                    if (!self.data.is_init) continue;
                    self.stop();

                    arg = args.peek() orelse {
                        self.search();
                        continue;
                    };

                    if (std.mem.eql(u8, arg, "perft")) {
                        _ = args.next();
                        arg = args.next() orelse "1";
                        const depth = try std.fmt.parseInt(u32, arg, 10);
                        _ = perft.perft(self.data.board, depth) catch continue;
                        continue;
                    }

                    if (std.mem.eql(u8, arg, "infinite")) {
                        self.data.search_thread = try std.Thread.spawn(
                            .{},
                            victoire.Engine.explore,
                            .{
                                &self.data.engine,
                                self.data.board,
                                ExplorerContext.init(&self.data.engine.infos.nodes),
                                explorer,
                            },
                        );
                        continue;
                    }

                    var time: ?i64 = null;
                    var movestogo: ?i64 = null;
                    var inc: i64 = 0;

                    while (args.next()) |a| {
                        if (std.mem.eql(u8, a, "depth")) {
                            arg = args.next() orelse break;
                            self.options.depth = try std.fmt.parseInt(u32, arg, 10);
                        }

                        if (std.mem.eql(u8, a, "movetime")) {
                            arg = args.next() orelse break;
                            self.options.time = try std.fmt.parseInt(i64, arg, 10);
                        }

                        if (std.mem.eql(u8, a, "movestogo")) {
                            arg = args.next() orelse break;
                            movestogo = try std.fmt.parseInt(i64, arg, 10);
                        }

                        if (std.mem.eql(u8, a, "wtime")) {
                            arg = args.next() orelse break;
                            if (self.data.board.side == .white) time = try std.fmt.parseInt(i64, arg, 10);
                        }

                        if (std.mem.eql(u8, a, "btime")) {
                            arg = args.next() orelse break;
                            if (self.data.board.side == .black) time = try std.fmt.parseInt(i64, arg, 10);
                        }

                        if (std.mem.eql(u8, a, "winc")) {
                            arg = args.next() orelse break;
                            if (self.data.board.side == .white) inc = try std.fmt.parseInt(i64, arg, 10);
                        }

                        if (std.mem.eql(u8, a, "binc")) {
                            arg = args.next() orelse break;
                            if (self.data.board.side == .black) inc = try std.fmt.parseInt(i64, arg, 10);
                        }
                    }

                    if (self.options.time_control and time != null) {
                        self.options.time = victoire.manageTime(time.?, inc, movestogo);
                    }

                    self.data.search_thread = try std.Thread.spawn(.{}, search, .{self});
                    continue;
                }

                if (std.mem.eql(u8, arg, "quit")) {
                    self.stop();
                    self.data.engine.deinit();
                    break;
                }

                if (std.mem.eql(u8, arg, "setoption")) {
                    arg = args.next() orelse continue;
                    arg = args.next() orelse continue;

                    if (std.mem.eql(u8, arg, "Hash")) {
                        arg = args.next() orelse continue;
                        arg = args.next() orelse continue;
                        self.options.table_size = std.fmt.parseInt(u64, arg, 10) catch continue;
                    }

                    if (std.mem.eql(u8, arg, "Ponder")) {
                        arg = args.next() orelse continue;
                        arg = args.next() orelse continue;
                        if (std.mem.eql(u8, arg, "true")) self.options.ponder = true;
                        if (std.mem.eql(u8, arg, "false")) self.options.ponder = false;
                    }

                    if (std.mem.eql(u8, arg, "TimeControl")) {
                        arg = args.next() orelse continue;
                        arg = args.next() orelse continue;
                        if (std.mem.eql(u8, arg, "true")) self.options.time_control = true;
                        if (std.mem.eql(u8, arg, "false")) self.options.time_control = false;
                    }
                }
            }
        }
    }

    fn stop(self: *Engine) void {
        self.data.engine.stop();
        if (self.data.search_thread != null) self.data.search_thread.?.join();
        if (self.data.ponder_thread != null) self.data.ponder_thread.?.join();
        self.data.search_thread = null;
        self.data.ponder_thread = null;
    }

    fn search(self: *Engine) void {
        const stdout = std.io.getStdOut().writer();
        const t0 = std.time.milliTimestamp();
        const result = self.data.engine.search(self.data.board, self.options.depth, self.options.time);
        const dt = std.time.milliTimestamp() - t0;

        var stringifier = io.MoveStringifier{};
        const checkmate = result.checkmate();

        stdout.print("info score ", .{}) catch unreachable;
        if (checkmate == null) stdout.print("cp {d} ", .{result.score}) catch unreachable;
        if (checkmate != null) stdout.print("mate {d} ", .{checkmate.?}) catch unreachable;
        stdout.print("depth {d} time {d} nodes {d} pv {s}\n", .{
            result.depth,
            dt,
            self.data.engine.infos.nodes,
            stringifier.stringify(result.best_move),
        }) catch unreachable;

        stdout.print("bestmove {s}\n", .{stringifier.stringify(result.best_move)}) catch unreachable;

        if (self.options.ponder) {
            const child = self.data.board.copyAndMake(result.best_move);
            self.data.ponder_thread = std.Thread.spawn(.{}, ponder, .{ self, child }) catch unreachable;
        }
    }

    fn ponder(self: *Engine, board: chess.Board) void {
        _ = self.data.engine.search(board, 100, null);
    }
};

const ExplorerContext = struct {
    t0: i64,
    nodes: *u64,

    pub fn init(nodes: *u64) ExplorerContext {
        return .{
            .t0 = std.time.milliTimestamp(),
            .nodes = nodes,
        };
    }
};

fn explorer(context: ExplorerContext, result: victoire.SearchResult) bool {
    const stdout = std.io.getStdOut().writer();
    const dt = std.time.milliTimestamp() - context.t0;
    const checkmate = result.checkmate();
    var stringifier = io.MoveStringifier{};

    stdout.print("info score ", .{}) catch unreachable;
    if (checkmate == null) stdout.print("cp {d} ", .{result.score}) catch unreachable;
    if (checkmate != null) stdout.print("mate {d} ", .{checkmate.?}) catch unreachable;

    stdout.print("depth {d} time {d} nodes {d} pv {s}\n", .{
        result.depth,
        dt,
        context.nodes.*,
        stringifier.stringify(result.best_move),
    }) catch unreachable;

    return false;
}
