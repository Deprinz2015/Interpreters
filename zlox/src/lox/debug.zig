const std = @import("std");

const Chunk = @import("Chunk.zig");

pub fn disassembleChunk(chunk: *Chunk, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.count()) {
        offset = disassembleInstruction(chunk, offset);
    }
}

pub fn disassembleInstruction(chunk: *Chunk, offset: usize) usize {
    std.debug.print("{x:0<4} ", .{offset});

    return switch (chunk.opAt(offset)) {
        .OP_RETURN => simpleInstruction("OP_RETURN", offset),
    };
}

fn simpleInstruction(instruction: []const u8, offset: usize) usize {
    std.debug.print("{s}\n", .{instruction});
    return offset + 1;
}
