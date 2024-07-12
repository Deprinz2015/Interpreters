const std = @import("std");
const GPA = std.heap.GeneralPurposeAllocator;

const Chunk = @import("lox/Chunk.zig");
const debug = @import("lox/debug.zig");

pub fn main() void {
    var gpa = GPA(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var chunk = Chunk.init(alloc);
    defer chunk.deinit();
    chunk.write(.OP_RETURN);
    debug.disassembleChunk(&chunk, "test chunk");
}
