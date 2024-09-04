const std = @import("std");
const Allocator = std.mem.Allocator;
const zli = @import("zli");

const Scanner = @import("compiler/Scanner.zig");
const Parser = @import("compiler/Parser.zig");
const Token = @import("compiler/Token.zig");

const ByteCodeCompiler = @import("bytecode/Compiler.zig");

const VM = @import("vm/Machine.zig");

const MAX_FILE_SIZE = 1024 * 1024; // 1 MB

const Error = error{
    FileError,
    SyntaxError,
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
            .printBytecode = .{ .type = bool, .desc = "Print the compiled Bytecode" },
            .run = .{ .type = bool, .short = 'r', .desc = "Run a .zox file. Only needed in combination with --compile" },
            .output = .{
                .type = []const u8,
                .short = 'o',
                .desc = "Alternative file path to output the compilation output",
                .value_hint = "PATH",
            },
        },
        .arguments = .{
            .input = .{
                .type = []const u8,
                .pos = 1,
                .desc = "Input file to run (or compile when using --compile)",
                .value_hint = "PATH",
            },
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
        const bytecode = try compile(alloc, input, parser.options.printAst);
        defer alloc.free(bytecode);

        if (parser.options.printBytecode) {
            try @import("debug/ByteCode.zig").print(bytecode);
        }

        if (parser.options.run) {
            try run(alloc, bytecode);
        } else {
            const output_file = parser.options.output orelse "program.zox";
            try save(alloc, output_file, bytecode);
        }
    } else {
        const code = try readFile(alloc, input);
        defer alloc.free(code);
        try run(alloc, code);
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

fn save(alloc: Allocator, filename: []const u8, code: []const u8) !void {
    _ = alloc;
    const file = std.fs.cwd().createFile(filename, .{}) catch {
        std.io.getStdErr().writer().print("Could not open file '{s}'\n", .{filename}) catch {};
        return Error.FileError;
    };
    defer file.close();

    try file.writer().writeAll(code);
}

fn compile(alloc: Allocator, input: []const u8, print_ast: bool) ![]u8 {
    const source = try readFile(alloc, input);
    defer alloc.free(source);

    var scanner = Scanner.init(source);
    var parser = Parser.init(alloc, &scanner);
    defer parser.deinit();

    const program = parser.parse() orelse {
        return Error.SyntaxError;
    };

    if (print_ast) {
        @import("debug/PrettyPrinter.zig").print(program) catch unreachable;
    }

    return try ByteCodeCompiler.translate(program, alloc);
}

fn run(alloc: Allocator, bytecode: []const u8) !void {
    var vm: VM = try .init(alloc, bytecode);
    defer vm.deinit();
    try vm.execute();
}
