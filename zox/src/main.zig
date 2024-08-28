const std = @import("std");
const Allocator = std.mem.Allocator;
const Zli = @import("Zli");
const Scanner = @import("compiler/Scanner.zig");
const Parser = @import("compiler/Parser.zig");
const Token = @import("compiler/Token.zig");

const MAX_FILE_SIZE = 1024 * 1024; // 1 MB

const Error = error{
    FileError,
};

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var zli = Zli.init(alloc);
    defer zli.deinit();

    try zli.addOption("help", 'h', "Show this Help message");
    try zli.addOption("compile", 'c', "Compile a .lox file into a .zox file");
    try zli.addOption("run", 'r', "Run a .zox file. Only needed in combination with --compile");
    try zli.addOption("output", 'o', "Alternative file path to output the compilation output");

    try zli.addArgument("input", "Either the .lox or .zox file to take in");

    if (try zli.option(bool, "help")) {
        return try zli.help(std.io.getStdOut().writer(), 0);
    }

    const input = zli.argument([]const u8, "input") catch return try zli.help(std.io.getStdOut().writer(), 64);

    if (try zli.option(bool, "compile")) {
        try compile(alloc, input);
        // TODO: Save bytecode to file or execute directly
        if (try zli.option(bool, "run")) {
            // TODO: execute bytecode
        } else {
            // TODO: save bytecode to .zox file
        }
    } else {
        // TODO: Read bytecode from file
        try run(alloc, "");
    }

    return 0;
}

fn readFile(alloc: Allocator, path: []const u8) ![]const u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch {
        std.io.getStdErr().writer().print("Could not open file '{s}'\n", .{path}) catch {};
        return Error.FileError;
    };
    defer file.close();

    const raw_content = file.readToEndAlloc(alloc, MAX_FILE_SIZE) catch |err| switch (err) {
        error.FileTooBig => {
            try std.io.getStdErr().writer().print("File '{s}' is to large. Maximum size is {d} bytes.\n", .{ path, MAX_FILE_SIZE });
            return err;
        },
        else => {
            try std.io.getStdErr().writer().print("Could not read file '{s}'.\n", .{path});
            return Error.FileError;
        },
    };

    return raw_content;
}

fn compile(alloc: Allocator, input: []const u8) !void {
    const source = try readFile(alloc, input);
    defer alloc.free(source);

    var scanner = Scanner.init(source);
    var parser = Parser.init(alloc, &scanner);
    defer parser.deinit();

    const ast = parser.parse();
    if (ast) |program| {
        @import("compiler/ast.zig").PrettyPrinter.print(program) catch unreachable;
    } else {
        std.debug.print("No tree :(\n", .{});
    }
}

fn run(alloc: Allocator, bytecode: []const u8) !void {
    // TODO: Execute bytecode
    _ = alloc;
    _ = bytecode;
    @panic("Not supported yet");
}
