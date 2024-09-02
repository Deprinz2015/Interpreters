const std = @import("std");
const Allocator = std.mem.Allocator;
const zli = @import("zli");
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

    var parser = try zli.Parser(.{
        .options = .{
            .help = .{ .type = bool, .short = 'h', .desc = "Show this Help message" },
            .compile = .{ .type = bool, .short = 'c', .desc = "Compile a .lox file into a .zox file" },
            .printAst = .{ .type = bool, .desc = "Print the generated AST before compiling to bytecode" },
            .run = .{ .type = bool, .short = 'r', .desc = "Run a .zox file. Only needed in combination with --compile" },
            .output = .{ .type = []const u8, .short = 'o', .desc = "Alternative file path to output the compilation output" },
        },
        .arguments = .{
            .input = .{ .type = []const u8, .pos = 1, .desc = "Alternative file path to output the compilation output" },
        },
    }).init(alloc);
    try parser.parse();
    defer parser.deinit();

    if (parser.options.help) {
        try parser.help(std.io.getStdOut().writer());
        return 0;
    }

    const input = parser.arguments.input orelse {
        try parser.help(std.io.getStdOut().writer());
        return 64;
    };

    if (parser.options.compile) {
        try compile(alloc, input, parser.options.printAst);
        // TODO: Save bytecode to file or execute directly
        if (parser.options.run) {
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

fn compile(alloc: Allocator, input: []const u8, print_ast: bool) !void {
    const source = try readFile(alloc, input);
    defer alloc.free(source);

    var scanner = Scanner.init(source);
    var parser = Parser.init(alloc, &scanner);
    defer parser.deinit();

    const ast = parser.parse();

    if (ast) |program| {
        if (print_ast) {
            @import("compiler/ast.zig").PrettyPrinter.print(program) catch unreachable;
        }
        std.debug.print("Compiling to bytecode...\n", .{});
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
