const std = @import("std");
const Allocator = std.mem.Allocator;
const StdOut = std.io.getStdOut();
const StdErr = std.io.getStdErr();
const GPA = std.heap.GeneralPurposeAllocator;

const Chunk = @import("lox/Chunk.zig");
const VM = @import("lox/VM.zig");
const GC = @import("lox/GC.zig");
const debug = @import("lox/debug.zig");

const MAX_FILE_SIZE = 10 * 1024; // 10kb

var vm: VM = undefined;

pub fn main() !u8 {
    var gpa = GPA(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var gc = GC.init(alloc);
    defer gc.deinit();

    vm = VM.init(alloc, &gc);
    gc.vm = &vm;
    defer vm.deinit();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len == 1) {
        try repl(alloc);
        return 0;
    }
    if (args.len == 2) {
        return try runFile(alloc, args[1]);
    }
    try StdErr.writeAll("Usage: zlox [path]\n");
    return 64;
}

fn repl(alloc: Allocator) !void {
    const StdIn = std.io.getStdIn();

    while (true) {
        try StdOut.writeAll("zlox> ");

        const input = StdIn.reader().readUntilDelimiterAlloc(alloc, '\n', 1024) catch {
            try StdOut.writeAll("\n");
            break;
        };
        defer alloc.free(input);

        if (std.mem.eql(u8, input, "exit")) {
            try StdOut.writeAll("\n");
            break;
        }

        _ = vm.interpret(alloc, input);
    }
}

fn runFile(alloc: Allocator, path: []const u8) !u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch {
        try StdErr.writer().print("Could not open file '{s}'.\n", .{path});
        return 74;
    };
    defer file.close();
    const source = file.readToEndAlloc(alloc, 10 * 1024) catch |err| switch (err) {
        error.FileTooBig => {
            try StdErr.writer().print("File '{s}' is to large. Maximum size is {d} bytes.\n", .{ path, MAX_FILE_SIZE });
            return 74;
        },
        else => {
            try StdErr.writer().print("Could not read file '{s}'.\n", .{path});
            return 74;
        },
    };
    defer alloc.free(source);

    const result = vm.interpret(alloc, source);

    if (result == .COMPILE_ERROR) {
        return 65;
    }
    if (result == .RUNTIME_ERROR) {
        return 70;
    }

    return 0;
}
