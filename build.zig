const std = @import("std");

const targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .x86_64, .os_tag = .windows },
    .{ .cpu_arch = .x86_64, .os_tag = .macos },
};

pub fn build(b: *std.Build) !void {
    for (targets) |target| {
        const exe = b.addExecutable(.{
            .name = "Victoire",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = b.resolveTargetQuery(target),
            .optimize = .ReleaseFast,
        });

        const name = try target.zigTriple(b.allocator);
        const out_dir = b.fmt("{s}/{s}", .{ b.install_path, name });

        const artifact = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{
            .custom = name,
        } } });

        const zip = b.addSystemCommand(&.{"zip"});
        zip.addArg("-rjqqFS");
        zip.addArg(b.fmt("{s}.zip", .{out_dir}));
        zip.addArg(out_dir);

        const tar = b.addSystemCommand(&.{"tar"});
        tar.addArg("-czf");
        tar.addArg(b.fmt("{s}.tar.gz", .{out_dir}));
        tar.addArg("-C");
        tar.addArg(b.install_path);
        tar.addArg(name);

        const rm = b.addSystemCommand(&.{"rm"});
        rm.addArg("-r");
        rm.addDirectoryArg(.{ .path = out_dir });

        zip.step.dependOn(&artifact.step);
        tar.step.dependOn(&artifact.step);
        rm.step.dependOn(&zip.step);
        if (target.os_tag != .windows) rm.step.dependOn(&tar.step);
        b.getInstallStep().dependOn(&rm.step);
    }
}
