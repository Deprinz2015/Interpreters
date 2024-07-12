const std = @import("std");
const Allocator = std.mem.Allocator;
const memory = @import("memory.zig");

const Chunk = @This();

pub const OpCode = enum(u8) {
    OP_RETURN,
};

code: []OpCode,
count: usize,
capacity: usize,
alloc: Allocator,

pub fn init(alloc: Allocator) Chunk {
    return .{
        .count = 0,
        .capacity = 0,
        .code = &.{},
        .alloc = alloc,
    };
}

pub fn write(self: *Chunk, byte: OpCode) void {
    if (self.capacity < self.count + 1) {
        const old_capacity = self.capacity;
        self.capacity = memory.growCapacity(old_capacity);
        self.code = self.alloc.realloc(self.code, self.capacity) catch unreachable;
    }

    self.code[self.count] = byte;
    self.count += 1;
}

/// Sets the chunk itself to undefined
pub fn deinit(self: *Chunk) void {
    self.alloc.free(self.code);
    self.count = 0;
    self.count = 0;
    self.* = undefined;
}
