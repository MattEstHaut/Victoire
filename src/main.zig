const uci = @import("uci.zig");

pub fn main() !void {
    var uci_engine = uci.Engine{};
    try uci_engine.run();
}
