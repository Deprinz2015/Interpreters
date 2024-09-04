const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = @import("../bytecode/value.zig").Value;
const Instruction = @import("../bytecode/instruction_set.zig").Instruction;

const VM = @This();

const STACK_MAX = 256;

alloc: Allocator,
constants: [256]Value,
code: []const u8,
ip: usize,
stack: []Value,
stack_top: usize,

const Error = error{
    UnexpectedInstruction,
};

pub fn init(alloc: Allocator, program: []const u8) !VM {
    return .{
        .alloc = alloc,
        .constants = undefined,
        .code = program,
        .ip = 0,
        .stack = try alloc.alloc(Value, STACK_MAX),
        .stack_top = 0,
    };
}

pub fn deinit(self: *VM) void {
    self.alloc.free(self.stack);
}

pub fn execute(self: *VM) !void {
    try self.loadConstants();
    try self.run();
}

fn loadConstants(self: *VM) !void {
    var constants_count: usize = 0;
    var idx: usize = 0;
    while (idx < self.code.len) {
        const code = self.code[idx];
        switch (code) {
            @intFromEnum(Instruction.CONSTANTS_DONE) => {
                self.ip = idx + 1;
                return;
            },
            @intFromEnum(Instruction.NUMBER) => {
                const number = std.mem.bytesToValue(f64, self.code[idx + 1 .. idx + 9]);
                self.constants[constants_count] = .{ .number = number };
                constants_count += 1;
                idx += 9; // 1 for instruction + 8 for 64-bit float
            },
            else => return Error.UnexpectedInstruction,
        }
    }
}

fn run(self: *VM) !void {
    _ = self;
}
