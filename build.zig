const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "test_skiplist",
        .root_source_file = std.Build.LazyPath.relative("skiplist.zig"),
        .optimize = optimize,
    });
    b.installArtifact(exe);
}
