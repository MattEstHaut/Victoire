//! This module contains the UCI engine.

const std = @import("std");
const io = @import("io.zig");
const chess = @import("chess.zig");
const victoire = @import("victoire.zig");
const perft = @import("perft.zig");

pub const Engine = struct {
    options: struct {
        depth: u32 = undefined,
        time: ?i64 = undefined,
    } = .{},

    data: struct {
        board: chess.Board = .{},
        engine: victoire.Engine = undefined,
        search_thread: ?std.Thread = null,
    } = .{},

    pub fn run(self: *Engine) !void {
        const stdin = std.io.getStdIn().reader();
        const stdout = std.io.getStdOut().writer();

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
                    try stdout.print("uciok\n", .{});
                    continue;
                }

                if (std.mem.eql(u8, arg, "ucinewgame")) {
                    self.data.engine = victoire.Engine.init();
                    continue;
                }

                if (std.mem.eql(u8, arg, "isready")) {
                    try stdout.print("uciok\n", .{});
                    continue;
                }

                if (std.mem.eql(u8, arg, "position")) {
                    arg = args.next() orelse continue;
                    if (std.mem.eql(u8, arg, "startpos")) {
                        self.data.board = try io.parsing.board("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
                    } else if (std.mem.eql(u8, arg, "fen")) {
                        arg = args.next() orelse continue;
                        self.data.board = try io.parsing.board(arg);
                    } else continue;

                    arg = args.next() orelse continue;
                    if (!std.mem.eql(u8, arg, "moves")) continue;

                    while (args.next()) |arg_move| {
                        const partial_move = try io.parsing.move(arg_move);
                        const move = try self.data.board.completeMove(partial_move);
                        self.data.board.make(move);
                    }

                    continue;
                }

                if (std.mem.eql(u8, arg, "go")) {
                    arg = args.peek() orelse {
                        self.search();
                        continue;
                    };

                    if (std.mem.eql(u8, arg, "perft")) {
                        _ = args.next();
                        arg = args.next() orelse "1";
                        const depth = try std.fmt.parseInt(u32, arg, 10);
                        _ = try perft.perft(self.data.board, depth);
                        continue;
                    }

                    self.options.depth = 10;
                    self.options.time = null;

                    while (args.next()) |a| {
                        if (std.mem.eql(u8, a, "depth")) {
                            arg = args.next() orelse break;
                            self.options.depth = try std.fmt.parseInt(u32, arg, 10);
                        }

                        if (std.mem.eql(u8, a, "time")) {
                            arg = args.next() orelse break;
                            self.options.time = try std.fmt.parseInt(i64, arg, 10);
                        }
                    }

                    self.search();

                    continue;
                }

                if (std.mem.eql(u8, arg, "quit")) {
                    self.data.engine.deinit();
                    break;
                }
            }
        }
    }

    fn search(self: *Engine) void {
        const stdout = std.io.getStdOut().writer();
        const t0 = std.time.milliTimestamp();
        const result = self.data.engine.search(self.data.board, self.options.depth, self.options.time);
        const dt = std.time.milliTimestamp() - t0;

        stdout.print("info score cp {d} depth {d} time {d}\n", .{
            result.score,
            result.depth,
            dt,
        }) catch unreachable;

        stdout.print("bestmove {s}\n", .{io.stringify(result.best_move)}) catch unreachable;
    }
};
