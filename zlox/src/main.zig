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
    const constant = chunk.addConstant(1.2);
    chunk.writeOpCode(.OP_CONSTANT, 123);
    chunk.writeByte(constant, 123);

    chunk.writeOpCode(.OP_RETURN, 123);
    debug.disassembleChunk(&chunk, "test chunk");
}
