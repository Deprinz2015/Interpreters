const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = @import("../bytecode/value.zig");
const Instruction = @import("../bytecode/instruction_set.zig").Instruction;

const VM = @This();

alloc: Allocator,
constants: [256]Value = undefined,
code: []const u8,
ip: usize = 0,

pub fn init(alloc: Allocator, program: []const u8) VM {
    return .{
        .alloc = alloc,
        .code = program,
    };
}

pub fn deinit(self: *VM) void {
    _ = self;
}

pub fn execute(self: *VM) !void {
    _ = self;
}
