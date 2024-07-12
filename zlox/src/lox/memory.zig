const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn growCapacity(capacity: usize) usize {
    if (capacity < 8) {
        return 8;
    }
    return capacity * 2;
}
