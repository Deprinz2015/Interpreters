const std = @import("std");

const Chunk = @import("Chunk.zig");
const Value = @import("value.zig").Value;

pub fn disassembleChunk(chunk: *Chunk, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.count) {
        offset = disassembleInstruction(chunk, offset);
    }
}

pub fn disassembleInstruction(chunk: *Chunk, offset: usize) usize {
    std.debug.print("{x:0>4} ", .{offset});
    if (offset > 0 and chunk.lines[offset] == chunk.lines[offset - 1]) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d:4} ", .{chunk.lines[offset]});
    }

    return switch (chunk.opAt(offset)) {
        .RETURN => simpleInstruction("OP_RETURN", offset),
        .CALL => byteInstruction("OP_CALL", chunk, offset),
        .POP => simpleInstruction("OP_POP", offset),
        .JUMP => jumpInstruction("OP_JUMP", 1, chunk, offset),
        .JUMP_IF_FALSE => jumpInstruction("OP_JUMP_IF_FALSE", 1, chunk, offset),
        .LOOP => jumpInstruction("OP_LOOP", -1, chunk, offset),
        .DEFINE_GLOBAL => constantInstruction("OP_DEFINE_GLOBAL", chunk, offset),
        .GET_GLOBAL => constantInstruction("OP_GET_GLOBAL", chunk, offset),
        .SET_GLOBAL => constantInstruction("OP_SET_GLOBAL", chunk, offset),
        .GET_LOCAL => byteInstruction("OP_GET_LOCAL", chunk, offset),
        .SET_LOCAL => byteInstruction("OP_SET_LOCAL", chunk, offset),
        .GET_UPVALUE => byteInstruction("OP_GET_UPVALUE", chunk, offset),
        .SET_UPVALUE => byteInstruction("OP_SET_UPVALUE", chunk, offset),
        .CONSTANT => constantInstruction("OP_CONSTANT", chunk, offset),
        .TRUE => simpleInstruction("OP_TRUE", offset),
        .FALSE => simpleInstruction("OP_FALSE", offset),
        .NIL => simpleInstruction("OP_NIL", offset),
        .NEGATE => simpleInstruction("OP_NEGATE", offset),
        .NOT => simpleInstruction("OP_NOT", offset),
        .EQUAL => simpleInstruction("OP_EQUAL", offset),
        .LESS => simpleInstruction("OP_LESS", offset),
        .GREATER => simpleInstruction("OP_GREATER", offset),
        .ADD => simpleInstruction("OP_ADD", offset),
        .SUBTRACT => simpleInstruction("OP_SUBTRACT", offset),
        .MULTIPLY => simpleInstruction("OP_MULTIPLY", offset),
        .DIVIDE => simpleInstruction("OP_DIVIDE", offset),
        .CLOSURE => closureInstruction(chunk, offset),
    };
}

fn simpleInstruction(instruction: []const u8, offset: usize) usize {
    std.debug.print("{s}\n", .{instruction});
    return offset + 1;
}

fn constantInstruction(name: []const u8, chunk: *Chunk, offset: usize) usize {
    const constant = chunk.byteAt(offset + 1);
    std.debug.print("{s: <16} {d: <4} '{}'\n", .{ name, constant, chunk.constantAt(constant) });
    return offset + 2;
}

fn jumpInstruction(name: []const u8, sign: i2, chunk: *Chunk, offset: usize) usize {
    var jump: u16 = @intCast(chunk.byteAt(offset + 1));
    jump = jump << 8 | chunk.byteAt(offset + 2);
    var jump_to: isize = sign * @as(isize, jump) + 3;
    jump_to += @intCast(offset);

    std.debug.print("{s: <16} {d: <4} -> {x}\n", .{ name, offset, jump_to });
    return offset + 3;
}

fn byteInstruction(name: []const u8, chunk: *Chunk, offset: usize) usize {
    const slot = chunk.code[offset + 1];
    std.debug.print("{s: <16} {d: <4}\n", .{ name, slot });
    return offset + 2;
}

fn closureInstruction(chunk: *Chunk, offset: usize) usize {
    var new_offset = offset + 1;
    const constant = chunk.byteAt(new_offset);
    new_offset += 1;
    std.debug.print("{s: <16} {d: <4} {}\n", .{ "OP_CLOSURE", constant, chunk.constantAt(constant) });

    const function = chunk.constantAt(constant).OBJ.as.FUNCTION;
    var i: usize = 0;
    while (i < function.upvalue_count) : (i += 1) {
        const is_local = chunk.byteAt(new_offset) == 1;
        const index = chunk.byteAt(new_offset + 1);
        std.debug.print("{d:0>4}      |                     {s} {d}\n", .{ new_offset, if (is_local) "local" else "upvalue", index });
        new_offset += 2;
    }
    return new_offset;
}
