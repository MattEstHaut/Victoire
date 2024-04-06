//! Contains the chess engine, search functions, and related functionalities.

const std = @import("std");
const chess = @import("chess.zig");
const movegen = @import("movegen.zig");
const transposition = @import("transposition.zig");
const evaluation = @import("evaluation.zig");

/// The Victory Chess Engine.
pub const Engine = struct {
    options: struct {} = .{},
    data: struct {} = .{},
    infos: struct {} = .{},
};
