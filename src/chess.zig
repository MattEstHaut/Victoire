//! This module contains the representation of a chessboard and related features.

const squares = @import("squares.zig");

pub const Piece = enum {
    pawn,
    knight,
    bishop,
    rook,
    queen,
    king,
};

const Positions = struct {
    pawns: u64 = 0,
    knights: u64 = 0,
    bishops: u64 = 0,
    rooks: u64 = 0,
    queens: u64 = 0,
    king: u64 = 0,

    occupied: u64 = 0,

    /// Returns the mask of a given piece.
    pub inline fn get(self: *Positions, piece: Piece) *u64 {
        return switch (piece) {
            .pawn => &self.pawns,
            .knight => &self.knights,
            .bishop => &self.bishops,
            .rook => &self.rooks,
            .queen => &self.queens,
            .king => &self.king,
        };
    }

    /// Returns the piece wich collides with the mask if any.
    pub inline fn collision(self: Positions, mask: u64) ?Piece {
        if (self.occupied & mask == 0) return null;
        if (self.pawns & mask > 0) return .pawn;
        if (self.knights & mask > 0) return .knight;
        if (self.bishops & mask > 0) return .bishop;
        if (self.rooks & mask > 0) return .rook;
        if (self.queens & mask > 0) return .queen;
        if (self.king & mask > 0) return .king;
        return null;
    }
};

pub const Color = enum {
    white,
    black,

    pub inline fn other(self: Color) Color {
        return switch (self) {
            .white => .black,
            .black => .white,
        };
    }
};

const Castling = enum {
    K, // White kingside
    Q, // White queenside
    k, // Black kingside
    q, // Black queenside
};

const CastlingRights = struct {
    K: bool = true,
    Q: bool = true,
    k: bool = true,
    q: bool = true,

    inline fn removeWhiteRights(self: *CastlingRights) void {
        self.K = false;
        self.Q = false;
    }

    inline fn removeBlackRights(self: *CastlingRights) void {
        self.k = false;
        self.q = false;
    }
};

const Promotion = enum {
    knight,
    bishop,
    rook,
    queen,
};

/// Representation of a move.
pub const Move = struct {
    src: u64 = 0,
    dest: u64 = 0,
    side: Color = .white,
    piece: Piece = .pawn,
    en_passant: bool = false,
    capture: ?Piece = null,
    promotion: ?Promotion = null,
    castling: ?Castling = null, // src and dest must be specified for king
    null_move: bool = false, // Only change side

    /// Compares two moves.
    pub inline fn sameAs(self: Move, other: Move) bool {
        if (self.src != other.src) return false;
        if (self.dest != other.dest) return false;
        if (self.promotion != other.promotion) return false;
        return true;
    }

    pub inline fn nullMove() Move {
        return .{ .null_move = true };
    }
};

/// Representation of a partial move (only source square, destination square and promotion if any).
pub const PartialMove = struct {
    src: u64 = 0,
    dest: u64 = 0,
    promotion: ?Promotion = null,
};

/// Representation of a chess board.
pub const Board = struct {
    white: Positions = .{},
    black: Positions = .{},

    side: Color = .white,
    castling_rights: CastlingRights = .{},
    en_passant: u64 = 0,

    halfmove_clock: u8 = 0, // Not implemented
    fullmove_number: u16 = 1, // Not implemented

    pub inline fn allies(self: *Board) *Positions {
        return switch (self.side) {
            .white => &self.white,
            .black => &self.black,
        };
    }

    pub inline fn enemies(self: *Board) *Positions {
        return switch (self.side) {
            .white => &self.black,
            .black => &self.white,
        };
    }

    /// Makes a move, doesn't check legality.
    pub inline fn make(self: *Board, move: Move) void {
        self.en_passant = 0;

        if (!move.null_move) {
            blk: {
                if (move.castling != null) {
                    const diff = switch (move.castling.?) {
                        .K => squares.h1 | squares.f1,
                        .Q => squares.a1 | squares.d1,
                        .k => squares.h8 | squares.f8,
                        .q => squares.a8 | squares.d8,
                    };
                    self.allies().rooks ^= diff;
                    self.allies().occupied ^= diff;
                    break :blk;
                }

                if (move.promotion != null) {
                    self.allies().pawns ^= move.dest;

                    break :blk switch (move.promotion.?) {
                        .knight => self.allies().knights ^= move.dest,
                        .bishop => self.allies().bishops ^= move.dest,
                        .rook => self.allies().rooks ^= move.dest,
                        .queen => self.allies().queens ^= move.dest,
                    };
                }

                if (move.piece == .pawn) {
                    if (move.src & squares.row_2 > 0 and move.dest & squares.row_4 > 0) {
                        self.en_passant = move.dest << 8;
                    } else if (move.src & squares.row_7 > 0 and move.dest & squares.row_5 > 0) {
                        self.en_passant = move.dest >> 8;
                    }
                }
            }

            const diff = move.src | move.dest;
            self.allies().get(move.piece).* ^= diff;
            self.allies().occupied ^= diff;

            if (move.capture != null) {
                const capture = blk: {
                    if (move.en_passant) break :blk if (move.side == .white) move.dest << 8 else move.dest >> 8;
                    break :blk move.dest;
                };

                switch (capture) {
                    squares.h1 => self.castling_rights.K = false,
                    squares.a1 => self.castling_rights.Q = false,
                    squares.h8 => self.castling_rights.k = false,
                    squares.a8 => self.castling_rights.q = false,
                    else => {},
                }

                self.enemies().occupied ^= capture;
                self.enemies().get(move.capture.?).* ^= capture;
            }

            switch (move.src) {
                squares.e1 => self.castling_rights.removeWhiteRights(),
                squares.e8 => self.castling_rights.removeBlackRights(),
                squares.a1 => self.castling_rights.Q = false,
                squares.h1 => self.castling_rights.K = false,
                squares.a8 => self.castling_rights.q = false,
                squares.h8 => self.castling_rights.k = false,
                else => {},
            }
        }

        self.side = self.side.other();
    }

    pub inline fn copyAndMake(self: Board, move: Move) Board {
        var child = self;
        child.make(move);
        return child;
    }

    /// Determines a Move from the Board and the PartialMove
    pub inline fn completeMove(self: Board, partial: PartialMove) !Move {
        var board = self;

        var move = Move{
            .src = partial.src,
            .dest = partial.dest,
            .side = board.side,
            .promotion = partial.promotion,
            .piece = board.allies().collision(partial.src) orelse return error.no_source_piece,
            .capture = board.enemies().collision(partial.dest),
        };

        if (move.dest == board.en_passant and move.piece == .pawn) move.en_passant = true;

        if (move.piece == .king) {
            if (move.src == squares.e1 and move.dest == squares.g1) move.castling = .K;
            if (move.src == squares.e1 and move.dest == squares.c1) move.castling = .Q;
            if (move.src == squares.e8 and move.dest == squares.g8) move.castling = .k;
            if (move.src == squares.e8 and move.dest == squares.c8) move.castling = .q;
        }

        return move;
    }
};
