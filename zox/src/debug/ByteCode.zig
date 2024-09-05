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
            .NUMBER => valueInstruction("OP_NUMBER", program, .number, offset),
            .STRING => valueInstruction("OP_STRING", program, .string, offset),
            .ADD => simpleInstruction("OP_ADD"),
            .SUB => simpleInstruction("OP_SUB"),
            .MUL => simpleInstruction("OP_MUL"),
            .DIV => simpleInstruction("OP_DIV"),
            .CONSTANT => constantInstruction("OP_CONSTANT", program[offset + 1]),
            .POP => simpleInstruction("OP_POP"),
            .PRINT => simpleInstruction("OP_PRINT"),
            .NIL => simpleInstruction("OP_NIL"),
            .TRUE => simpleInstruction("OP_TRUE"),
            .FALSE => simpleInstruction("OP_FALSE"),
            .NOT => simpleInstruction("OP_NOT"),
            .NEGATE => simpleInstruction("OP_NEGATE"),
            .EQUAL => simpleInstruction("OP_EQUAL"),
            .NOT_EQUAL => simpleInstruction("OP_NOT_EQUAL"),
            .LESS => simpleInstruction("OP_LESS"),
            .LESS_EQUAL => simpleInstruction("OP_LESS_EQUAL"),
            .GREATER => simpleInstruction("OP_GREATER"),
            .GREATER_EQUAL => simpleInstruction("OP_GREATER_EQUAL"),
        };
    }
}

fn simpleInstruction(name: []const u8) usize {
    std.debug.print("{s}\n", .{name});
    return 1;
}

fn valueInstruction(name: []const u8, program: []u8, value_type: std.meta.Tag(Value), offset: usize) usize {
    std.debug.print("{s: <24} ", .{name});
    var new_offset: usize = 0;
    switch (value_type) {
        .number => {
            const value = std.mem.bytesToValue(f64, program[offset + 1 .. offset + 9]);
            std.debug.print("{d}", .{value});
            new_offset = 8;
        },
        .string => {
            const len = len: {
                const lhs: u16 = @intCast(program[offset + 1]);
                const rhs: u16 = @intCast(program[offset + 2]);
                break :len (lhs << 8) | rhs;
            };

            const value = program[offset + 3 .. offset + 3 + len];
            std.debug.print("{s}", .{value});

            new_offset = 2 + len;
        },
        else => @panic("Unsupported value type"),
    }
    std.debug.print("\n", .{});
    return new_offset + 1;
}

fn constantInstruction(name: []const u8, idx: u8) usize {
    std.debug.print("{s: <24} {d}\n", .{ name, idx });
    return 2;
}
