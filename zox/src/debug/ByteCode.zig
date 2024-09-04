const std = @import("std");
const Instruction = @import("../bytecode/instruction_set.zig").Instruction;
const Value = @import("../bytecode/value.zig").Value;

pub fn print(program: []u8) !void {
    if (program.len == 0) {
        return;
    }

    const offset = switch (program[0]) {
        @intFromEnum(Instruction.CONSTANTS_DONE) => simpleInstruction("OP_CONSTANTS_DONE"),
        @intFromEnum(Instruction.NUMBER) => valueInstruction("OP_NUMBER", program, .number),
        @intFromEnum(Instruction.ADD) => simpleInstruction("OP_ADD"),
        @intFromEnum(Instruction.SUB) => simpleInstruction("OP_SUB"),
        @intFromEnum(Instruction.MUL) => simpleInstruction("OP_MUL"),
        @intFromEnum(Instruction.DIV) => simpleInstruction("OP_DIV"),
        @intFromEnum(Instruction.CONSTANT) => constantInstruction("OP_CONSTANT", program[1]),
        @intFromEnum(Instruction.POP) => simpleInstruction("OP_POP"),
        else => @panic("Unsupported Instruction"),
    };
    try print(program[offset..]);
}

fn simpleInstruction(name: []const u8) usize {
    std.debug.print("{s}\n", .{name});
    return 1;
}

fn valueInstruction(name: []const u8, program: []u8, value_type: std.meta.Tag(Value)) usize {
    std.debug.print("{s} ", .{name});
    var offset: usize = 0;
    switch (value_type) {
        .number => {
            const value = std.mem.bytesToValue(f64, program[1..9]);
            std.debug.print("{d}", .{value});
            offset = 8;
        },
    }
    std.debug.print("\n", .{});
    return offset + 1;
}

fn constantInstruction(name: []const u8, idx: u8) usize {
    std.debug.print("{s} {d}\n", .{ name, idx });
    return 2;
}
