//! This module contains the UCI engine.

const std = @import("std");
const io = @import("io.zig");
const chess = @import("chess.zig");
const victoire = @import("victoire.zig");
const perft = @import("perft.zig");

pub const Engine = struct {
    options: struct {
        depth: u32 = 10,
    } = .{},

    data: struct {
        board: chess.Board = .{},
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
                    try stdout.print("option name depth type spin default {d} min 1 max 30\n", .{self.options.depth});
                    try stdout.print("uciok\n", .{});
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
                    arg = args.next() orelse continue;

                    if (std.mem.eql(u8, arg, "perft")) {
                        arg = args.next() orelse "1";
                        const depth = try std.fmt.parseInt(u32, arg, 10);
                        _ = try perft.perft(self.data.board, depth);
                    }

                    continue;
                }

                if (std.mem.eql(u8, arg, "quit")) {
                    break;
                }
            }
        }
    }
};
