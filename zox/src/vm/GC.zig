const std = @import("std");
const Allocator = std.mem.Allocator;

const DEBUG_OUTPUT = true;

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
        if (DEBUG_OUTPUT) {
            std.debug.print("[GC] cleaning up addr 0x{x}\n", .{getPtrFromValue(obj.value)});
        }

        obj.value.destroy(self.alloc);
    }
    self.ref_counts.deinit();
}

/// If value does not need to be counted, this is a no-op
pub fn count(self: *GC, value: Value) !void {
    if (!isGarbageCollected(value)) return;

    const ptr = getPtrFromValue(value);
    try self.ref_counts.put(ptr, .{ .count = 1, .value = value });

    if (DEBUG_OUTPUT) {
        std.debug.print("[GC] started counting addr 0x{x} with value {}\n", .{ ptr, value });
    }
}

pub fn countUp(self: *GC, value: Value) !void {
    if (!isGarbageCollected(value)) return;
    const ptr = getPtrFromValue(value);

    if (self.ref_counts.getPtr(ptr)) |count_ptr| {
        if (DEBUG_OUTPUT) {
            std.debug.print("[GC] increment addr 0x{x}\n", .{ptr});
        }
        count_ptr.count += 1;
    } else {
        return Error.UntrackedMemory;
    }
}

pub fn countDown(self: *GC, value: Value) !void {
    if (!isGarbageCollected(value)) return;
    const ptr = getPtrFromValue(value);

    if (self.ref_counts.getPtr(ptr)) |count_ptr| {
        if (DEBUG_OUTPUT) {
            std.debug.print("[GC] decrement addr 0x{x}\n", .{ptr});
        }
        if (count_ptr.count > 1) {
            count_ptr.count -= 1;
            return;
        }

        if (DEBUG_OUTPUT) {
            std.debug.print("[GC] freeing addr 0x{x}\n", .{ptr});
        }

        count_ptr.value.destroy(self.alloc);
        _ = self.ref_counts.remove(ptr);
    } else {
        return Error.UntrackedMemory;
    }
}

fn isGarbageCollected(value: Value) bool {
    return value == .string;
}

fn getPtrFromValue(value: Value) usize {
    return switch (value) {
        .string => @intFromPtr(value.string),
        else => @panic("This value is not garbage collected"),
    };
}
