const std = @import("std");
const Allocator = std.mem.Allocator;
const DynamicArray = @import("containers.zig").DynamicArray;
const ValueArray = @import("value.zig").ValueArray;
const Value = @import("value.zig").Value;

const Chunk = @This();

pub const OpCode = enum(u8) {
    OP_RETURN,
    OP_CONSTANT,
};

code: DynamicArray(u8),
constants: ValueArray,
alloc: Allocator,

pub fn init(alloc: Allocator) Chunk {
    var chunk: Chunk = .{
        .alloc = alloc,
        .code = undefined,
        .constants = undefined,
    };
    chunk.code = DynamicArray(u8).init(chunk.alloc);
    chunk.constants = ValueArray.init(chunk.alloc);
    return chunk;
}

pub fn writeByte(self: *Chunk, byte: u8) void {
    self.code.write(byte);
}

pub fn writeOpCode(self: *Chunk, byte: OpCode) void {
    self.code.write(@intFromEnum(byte));
}

pub fn addConstant(self: *Chunk, value: Value) u8 {
    self.constants.write(value);
    return self.constants.count() - 1;
}

pub fn opAt(self: *Chunk, offset: usize) OpCode {
    return @enumFromInt(self.code.entries[offset]);
}

pub fn byteAt(self: *Chunk, offset: usize) OpCode {
    return self.code.entries[offset];
}

pub fn count(self: *Chunk) usize {
    return self.code.count;
}

/// Sets the chunk itself to undefined
pub fn deinit(self: *Chunk) void {
    self.code.deinit();
    self.constants.deinit();
    self.* = undefined;
}
