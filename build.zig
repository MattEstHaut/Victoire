const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .os_tag = .freestanding,
        .cpu_arch = .wasm32,
    });

    const exe = b.addExecutable(.{
        .name = "Victoire",
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = .ReleaseFast,
    });

    exe.global_base = 6560;
    exe.entry = .disabled;
    exe.rdynamic = true;
    exe.import_memory = true;
    exe.stack_size = std.wasm.page_size;

    exe.initial_memory = std.wasm.page_size * 2048;
    exe.max_memory = std.wasm.page_size * 2048 * 16;

    b.installArtifact(exe);
}
