const std = @import("std");
const Instruction = @import("../bytecode/instruction_set.zig").Instruction;
const Value = @import("../bytecode/value.zig").Value;

pub fn print(program: []u8) !void {
    if (program.len == 0) {
        return;
    }

    var offset: usize = 0;
    while (offset < program.len) {
        std.debug.print("{x:0>4} ", .{offset});
        const instruction: Instruction = @enumFromInt(program[offset]);
        offset += switch (instruction) {
            .CONSTANTS_DONE => simpleInstruction("OP_CONSTANTS_DONE"),
            .NUMBER => valueInstruction("OP_NUMBER", program, .number),
            .ADD => simpleInstruction("OP_ADD"),
            .SUB => simpleInstruction("OP_SUB"),
            .MUL => simpleInstruction("OP_MUL"),
            .DIV => simpleInstruction("OP_DIV"),
            .CONSTANT => constantInstruction("OP_CONSTANT", program[1]),
            .POP => simpleInstruction("OP_POP"),
            .PRINT => simpleInstruction("OP_PRINT"),
        };
    }
}

fn simpleInstruction(name: []const u8) usize {
    std.debug.print("{s}\n", .{name});
    return 1;
}

fn valueInstruction(name: []const u8, program: []u8, value_type: std.meta.Tag(Value)) usize {
    std.debug.print("{s: <24} ", .{name});
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
    std.debug.print("{s: <24} {d}\n", .{ name, idx });
    return 2;
}
