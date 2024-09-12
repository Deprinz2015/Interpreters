const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const debug_gc = b.option(bool, "debug-gc", "Enable Debugging Output of GC");
    const debug_stack = b.option(bool, "debug-stack", "Enable Debugging Output of Value Stack");
    const debug_local = b.option(bool, "debug-local", "Enable Debugging Output of Locals Stack");

    const zli = b.dependency("zli", .{ .target = target, .optimize = optimize });

    var config = b.addOptions();
    config.addOption(bool, "DEBUG_GC", debug_gc orelse (optimize == .Debug));
    config.addOption(bool, "DEBUG_STACK", debug_stack orelse (optimize == .Debug));
    config.addOption(bool, "DEBUG_LOCAL", debug_local orelse (optimize == .Debug));

    const exe = b.addExecutable(.{
        .name = "zox",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zli", zli.module("zli"));
    exe.root_module.addOptions("config", config);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
