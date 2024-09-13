const std = @import("std");
const Allocator = std.mem.Allocator;

const DEBUG_OUTPUT = @import("config").DEBUG_GC;

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

        self.deinitValue(obj.value);
    }
    self.ref_counts.deinit();
}

pub fn countUp(self: *GC, value: Value) !void {
    if (!isGarbageCollected(value)) return;
    const ptr = getPtrFromValue(value);

    const gop = try self.ref_counts.getOrPut(ptr);

    if (gop.found_existing) {
        gop.value_ptr.count += 1;
    } else {
        gop.value_ptr.* = .{ .count = 1, .value = value };
    }
    if (DEBUG_OUTPUT) {
        std.debug.print("[GC] increment addr 0x{x} for value '{}', count at {d}\n", .{ ptr, value, gop.value_ptr.count });
    }
}

pub fn countDown(self: *GC, value: Value) void {
    if (!isGarbageCollected(value)) return;
    const ptr = getPtrFromValue(value);

    if (self.ref_counts.getPtr(ptr)) |count_ptr| {
        if (DEBUG_OUTPUT) {
            std.debug.print("[GC] decrement addr 0x{x} for value '{}', count at {d}\n", .{ ptr, value, count_ptr.count - 1 });
        }
        if (count_ptr.count > 1) {
            count_ptr.count -= 1;
            return;
        }

        if (DEBUG_OUTPUT) {
            std.debug.print("[GC] freeing addr 0x{x}\n", .{ptr});
        }

        self.destroy(count_ptr.value);
        _ = self.ref_counts.remove(ptr);
    }
}

fn isGarbageCollected(value: Value) bool {
    return value == .string or value == .closure;
}

fn getPtrFromValue(value: Value) usize {
    return switch (value) {
        .string => @intFromPtr(value.string),
        .closure => @intFromPtr(value.closure),
        else => @panic("This value is not garbage collected"),
    };
}

pub fn destroy(self: *GC, value: Value) void {
    switch (value) {
        .number, .boolean, .nil, .native, .function => unreachable,
        .string => self.alloc.destroy(value.string),
        .closure => {
            for (value.closure.upvalues) |upvalue| {
                self.countDown(upvalue);
            }
            self.alloc.free(value.closure.upvalues);
            self.alloc.destroy(value.closure);
        },
    }
}

pub fn deinitValue(self: *GC, value: Value) void {
    switch (value) {
        .number, .boolean, .nil, .native, .function => unreachable,
        .string => self.alloc.destroy(value.string),
        .closure => {
            self.alloc.free(value.closure.upvalues);
            self.alloc.destroy(value.closure);
        },
    }
}
