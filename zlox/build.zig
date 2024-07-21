const std = @import("std");

const Options = struct {
    stack_trace: bool,
    chunk_trace: bool,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

pub fn build(b: *std.Build) void {
    const debug = b.option(bool, "debug", "Enable all tracing and debugging infos") orelse false;
    const stack_trace = b.option(bool, "stack-trace", "Enable debug tracing of Value Stack") orelse debug;
    const chunk_trace = b.option(bool, "chunk-trace", "Enable debug tracing of Chunks") orelse debug;

    var options: Options = .{
        .chunk_trace = chunk_trace,
        .stack_trace = stack_trace,
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    };

    const exe = makeStep(b, options);

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // some defaults for check
    options.stack_trace = true;
    options.chunk_trace = true;

    const exe_check = makeStep(b, options);
    const check = b.step("check", "Check if compiles");
    check.dependOn(&exe_check.step);
}

fn makeStep(b: *std.Build, options: Options) *std.Build.Step.Compile {
    const step = b.addExecutable(.{
        .name = "zlox",
        .root_source_file = b.path("src/main.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });

    var config = b.addOptions();
    config.addOption(bool, "stack_trace", options.stack_trace);
    config.addOption(bool, "chunk_trace", options.chunk_trace);
    step.root_module.addOptions("config", config);

    return step;
}
