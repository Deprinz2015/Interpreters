const std = @import("std");
const Allocator = std.mem.Allocator;

const DynamicArray = @import("containers.zig").DynamicArray;

pub const Value = f32;

pub const ValueArray = struct {
    alloc: Allocator,
    values: DynamicArray(Value),

    pub fn init(alloc: Allocator) ValueArray {
        var value_array: ValueArray = .{
            .alloc = alloc,
            .values = undefined,
        };
        value_array.values = DynamicArray(Value).init(value_array.alloc);
        return value_array;
    }

    pub fn write(self: *ValueArray, byte: Value) void {
        // TODO: Add check if amount of values is not to big
        self.values.write(byte);
    }

    pub fn at(self: *ValueArray, offset: usize) Value {
        return self.values.entries[offset];
    }

    pub fn count(self: *ValueArray) u8 {
        // TODO: Add check if amount of values is not to big
        return @intCast(self.values.count);
    }

    /// Sets the value_array itself to undefined
    pub fn deinit(self: *ValueArray) void {
        self.values.deinit();
        self.* = undefined;
    }
};
