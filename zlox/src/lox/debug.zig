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
        .CONSTANT => constantInstruction("OP_CONSTANT", chunk, offset),
        .NEGATE => simpleInstruction("OP_NEGATE", offset),
        .ADD => simpleInstruction("OP_ADD", offset),
        .SUBTRACT => simpleInstruction("OP_SUBTRACT", offset),
        .MULTIPLY => simpleInstruction("OP_MULTIPLY", offset),
        .DIVIDE => simpleInstruction("OP_DIVIDE", offset),
    };
}

fn simpleInstruction(instruction: []const u8, offset: usize) usize {
    std.debug.print("{s}\n", .{instruction});
    return offset + 1;
}

fn constantInstruction(name: []const u8, chunk: *Chunk, offset: usize) usize {
    const constant = chunk.byteAt(offset + 1);
    std.debug.print("{s: <16} {d: <4}'", .{ name, constant });
    printValue(chunk.constantAt(constant));
    std.debug.print("'\n", .{});
    return offset + 2;
}

pub fn printValue(value: Value) void {
    std.debug.print("{d}", .{value});
}
