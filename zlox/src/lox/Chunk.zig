const std = @import("std");
const Allocator = std.mem.Allocator;
const ValueArray = @import("value.zig").ValueArray;
const Value = @import("value.zig").Value;

const Chunk = @This();

pub const OpCode = enum(u8) {
    RETURN,
    CONSTANT,
    TRUE,
    FALSE,
    NIL,
    NEGATE,
    ADD,
    SUBTRACT,
    MULTIPLY,
    DIVIDE,
};

code: []u8,
lines: []usize,
capacity: usize,
count: usize,
constants: ValueArray,
alloc: Allocator,

pub fn init(alloc: Allocator) Chunk {
    var chunk: Chunk = .{
        .alloc = alloc,
        .code = &.{},
        .lines = &.{},
        .capacity = 0,
        .count = 0,
        .constants = undefined,
    };
    chunk.constants = ValueArray.init(chunk.alloc);
    return chunk;
}

pub fn writeByte(self: *Chunk, byte: u8, line: usize) void {
    if (self.capacity < self.count + 1) {
        self.growCapacity();
        self.code = self.alloc.realloc(self.code, self.capacity) catch unreachable;
        self.lines = self.alloc.realloc(self.lines, self.capacity) catch unreachable;
    }

    self.code[self.count] = byte;
    self.lines[self.count] = line;
    self.count += 1;
}

pub fn writeOpCode(self: *Chunk, byte: OpCode, line: usize) void {
    self.writeByte(@intFromEnum(byte), line);
}

pub fn write(self: *Chunk, comptime raw: bool, byte: (if (raw) u8 else OpCode), line: usize) void {
    if (raw) {
        self.writeByte(byte, line);
    } else {
        self.writeOpCode(byte, line);
    }
}

pub fn addConstant(self: *Chunk, value: Value) usize {
    self.constants.write(value);
    return self.constants.count - 1;
}

pub fn opAt(self: *Chunk, offset: usize) OpCode {
    return @enumFromInt(self.code[offset]);
}

pub fn byteAt(self: *Chunk, offset: usize) u8 {
    return self.code[offset];
}

pub fn constantAt(self: *Chunk, offset: usize) Value {
    return self.constants.at(offset);
}

/// Sets the chunk itself to undefined
pub fn deinit(self: *Chunk) void {
    self.alloc.free(self.code);
    self.alloc.free(self.lines);
    self.constants.deinit();
    self.capacity = 0;
    self.count = 0;
    self.* = undefined;
}

fn growCapacity(self: *Chunk) void {
    if (self.capacity < 8) {
        self.capacity = 8;
        return;
    }
    self.capacity *= 2;
}
