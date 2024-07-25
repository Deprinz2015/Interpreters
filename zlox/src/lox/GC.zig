const std = @import("std");
const Allocator = std.mem.Allocator;

const DEBUG_STRESS_GC = @import("config").stress_gc;
const DEBUG_LOG_GC = @import("config").log_gc;

const GC = @This();

child_alloc: Allocator,

pub fn init(child_alloc: Allocator) GC {
    return .{
        .child_alloc = child_alloc,
    };
}

pub fn deinit(self: *GC) void {
    _ = self;
}

pub fn allocator(self: *GC) Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .free = free,
        },
    };
}

fn collectGarbage(_: *GC) void {
    if (comptime DEBUG_LOG_GC) {
        std.debug.print("-- gc begin\n", .{});
    }

    if (comptime DEBUG_LOG_GC) {
        std.debug.print("-- gc end\n", .{});
    }
}

fn alloc(ctx: *anyopaque, n: usize, log2_ptr_align: u8, ra: usize) ?[*]u8 {
    const self: *GC = @ptrCast(@alignCast(ctx));
    if (comptime DEBUG_STRESS_GC) {
        self.collectGarbage();
    }
    return self.child_alloc.rawAlloc(n, log2_ptr_align, ra);
}

fn resize(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, new_len: usize, ret_addr: usize) bool {
    const self: *GC = @ptrCast(@alignCast(ctx));

    if (comptime DEBUG_STRESS_GC) {
        if (new_len > buf.len) {
            self.collectGarbage();
        }
    }

    return self.child_alloc.rawResize(buf, log2_buf_align, new_len, ret_addr);
}

fn free(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, ret_addr: usize) void {
    const self: *GC = @ptrCast(@alignCast(ctx));
    self.child_alloc.rawFree(buf, log2_buf_align, ret_addr);
}
