const std = @import("std");
const GPA = std.heap.GeneralPurposeAllocator;

const Chunk = @import("lox/Chunk.zig");
const VM = @import("lox/VM.zig");
const debug = @import("lox/debug.zig");

pub fn main() void {
    var gpa = GPA(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var vm = VM.init();
    defer vm.deinit();

    var chunk = Chunk.init(alloc);
    defer chunk.deinit();
    var constant = chunk.addConstant(1.2);
    chunk.writeOpCode(.CONSTANT, 123);
    chunk.writeByte(constant, 123);

    constant = chunk.addConstant(3.4);
    chunk.writeOpCode(.CONSTANT, 123);
    chunk.writeByte(constant, 123);

    chunk.writeOpCode(.ADD, 123);

    constant = chunk.addConstant(5.6);
    chunk.writeOpCode(.CONSTANT, 123);
    chunk.writeByte(constant, 123);

    chunk.writeOpCode(.DIVIDE, 123);
    chunk.writeOpCode(.NEGATE, 123);

    chunk.writeOpCode(.RETURN, 123);
    debug.disassembleChunk(&chunk, "test chunk");

    _ = vm.interpret(&chunk);
}
