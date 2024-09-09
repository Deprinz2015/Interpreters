const std = @import("std");
const Allocator = std.mem.Allocator;

const Value = @import("value.zig").Value;

const Error = error{
    UntrackedMemory,
};

const GC = @This();

const RefCountEntry = struct {
    count: usize,
    value: Value,
};

alloc: Allocator,
ref_counts: std.AutoHashMap(usize, RefCountEntry),

pub fn init(child_alloc: Allocator) GC {
    return .{
        .alloc = child_alloc,
        .ref_counts = .init(child_alloc),
    };
}

/// Frees all memory not yet collected
pub fn deinit(self: *GC) void {
    var counted_objs = self.ref_counts.valueIterator();
    while (counted_objs.next()) |obj| {
        obj.value.destroy(self.alloc);
    }
    self.ref_counts.deinit();
}

/// If value does not need to be counted, this is a no-op
pub fn count(self: *GC, value: Value) !void {
    switch (value) {
        .nil, .number, .boolean => return,
        .string => {
            try self.ref_counts.put(@intFromPtr(value.string), .{ .count = 1, .value = value });
        },
    }
}

pub fn countUp(self: *GC, value: Value) !void {
    const ptr = switch (value) {
        .nil, .number, .boolean => return,
        .string => @intFromPtr(value.string),
    };

    if (self.ref_counts.getPtr(ptr)) |count_ptr| {
        count_ptr.count += 1;
    } else {
        return Error.UntrackedMemory;
    }
}

pub fn countDown(self: *GC, value: Value) !void {
    const ptr = switch (value) {
        .nil, .number, .boolean => return,
        .string => @intFromPtr(value.string),
    };

    if (self.ref_counts.getPtr(ptr)) |count_ptr| {
        if (count_ptr.count > 1) {
            count_ptr.count -= 1;
            return;
        }

        count_ptr.value.destroy(self.alloc);
        _ = self.ref_counts.remove(ptr);
    } else {
        return Error.UntrackedMemory;
    }
}
