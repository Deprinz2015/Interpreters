const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn DynamicArray(comptime T: type) type {
    return struct {
        capacity: usize,
        count: usize,
        entries: []T,
        alloc: Allocator,

        pub fn init(alloc: Allocator) @This() {
            return .{
                .count = 0,
                .capacity = 0,
                .entries = &.{},
                .alloc = alloc,
            };
        }

        fn growCapacity(self: *@This()) void {
            if (self.capacity < 8) {
                self.capacity = 8;
                return;
            }
            self.capacity *= 2;
        }

        pub fn write(self: *@This(), entry: T) void {
            if (self.capacity < self.count + 1) {
                self.growCapacity();
                self.entries = self.alloc.realloc(self.entries, self.capacity) catch unreachable;
            }

            self.entries[self.count] = entry;
            self.count += 1;
        }

        /// Sets itself to undefined
        pub fn deinit(self: *@This()) void {
            self.alloc.free(self.entries);
            self.count = 0;
            self.capacity = 0;
            self.* = undefined;
        }
    };
}
