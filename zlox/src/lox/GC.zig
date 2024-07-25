const std = @import("std");
const Allocator = std.mem.Allocator;

const DEBUG_STRESS_GC = @import("config").stress_gc;
const DEBUG_LOG_GC = @import("config").log_gc;

const VM = @import("VM.zig");
const Compiler = @import("Compiler.zig").Compiler;
const Value = @import("value.zig").Value;
const ValueArray = @import("value.zig").ValueArray;
const Obj = @import("value.zig").Obj;

const GC = @This();

child_alloc: Allocator,
vm: *VM,
compiler: ?*Compiler,
gray_stack: []*Obj,
gray_count: usize,
gray_size: usize,

/// Manually set .vm before first usage
pub fn init(child_alloc: Allocator) GC {
    return .{
        .child_alloc = child_alloc,
        .vm = undefined,
        .compiler = null,
        .gray_count = 0,
        .gray_size = 0,
        .gray_stack = &.{},
    };
}

pub fn deinit(self: *GC) void {
    self.child_alloc.free(self.gray_stack);
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

fn markTable(self: *GC, table: *std.StringHashMap(Value)) void {
    var iter = table.iterator();
    while (iter.next()) |value| {
        self.markValue(value.value_ptr.*);
    }
}

pub fn markObject(self: *GC, maybe_obj: ?*Obj) void {
    if (maybe_obj == null) {
        return;
    }

    const obj = maybe_obj.?;
    if (obj.is_marked) {
        return;
    }

    obj.is_marked = true;

    if (comptime DEBUG_LOG_GC) {
        std.debug.print("{*} mark {}\n", .{ obj, &Value{ .OBJ = obj } });
    }

    if (self.gray_size < self.gray_count + 1) {
        self.gray_size = if (self.gray_size < 8) 8 else self.gray_size * 2;
        self.gray_stack = self.child_alloc.realloc(self.gray_stack, self.gray_size) catch unreachable;
    }

    self.gray_stack[self.gray_count] = obj;
    self.gray_count += 1;
}

fn markValue(self: *GC, value: Value) void {
    if (value != .OBJ) {
        return;
    }

    self.markObject(value.OBJ);
}

fn markRoots(self: *GC) void {
    for (self.vm.stack, 0..) |slot, i| {
        if (i >= self.vm.stack_top) {
            break;
        }

        self.markValue(slot);
    }

    for (self.vm.frames, 0..) |frame, i| {
        if (i >= self.vm.frame_count) {
            break;
        }
        self.markObject(&frame.closure.obj);
    }

    var maybe_upvalue = self.vm.open_upvalues;
    while (maybe_upvalue) |upvalue| {
        defer maybe_upvalue = upvalue.next;
        self.markObject(&upvalue.obj);
    }

    self.markTable(&self.vm.globals);
    if (self.compiler) |compiler| {
        compiler.markCompilerRoots(self);
    }
}

fn markArray(self: *GC, array: *ValueArray) void {
    var i: usize = 0;
    while (i < array.count) : (i += 1) {
        self.markValue(array.at(i));
    }
}

fn blackenObject(self: *GC, obj: *Obj) void {
    if (comptime DEBUG_LOG_GC) {
        std.debug.print("{*} blacken {}\n", .{ obj, &Value{ .OBJ = obj } });
    }

    switch (obj.type) {
        .STRING, .NATIVE => {},
        .UPVALUE => self.markValue(obj.as(.UPVALUE).closed),
        .FUNCTION => {
            const function = obj.as(.FUNCTION);
            if (function.name) |name| {
                self.markObject(&name.obj);
            }
            self.markArray(&function.chunk.constants);
        },
        .CLOSURE => {
            const closure = obj.as(.CLOSURE);
            self.markObject(&closure.function.obj);
            for (closure.upvalues) |maybe_upvalue| {
                if (maybe_upvalue) |upvalue| {
                    self.markObject(&upvalue.obj);
                }
            }
        },
    }
}

fn traceReferences(self: *GC) void {
    while (self.gray_count > 0) {
        const obj = self.gray_stack[self.gray_count - 1];
        self.gray_count -= 1;
        self.blackenObject(obj);
    }
}

fn sweep(self: *GC) void {
    var previous: ?*Obj = null;
    var maybe_object = self.vm.objects;
    while (maybe_object) |object| {
        if (object.is_marked) {
            object.is_marked = false;
            previous = object;
            maybe_object = object.next;
            continue;
        }

        const unreached = object;
        maybe_object = object.next;
        if (previous) |prev| {
            prev.next = maybe_object;
        } else {
            self.vm.objects = maybe_object;
        }

        unreached.destroy(self.child_alloc);
    }
}

fn removeWhiteStrings(self: *GC) void {
    var iter = self.vm.strings.iterator();
    var to_remove = std.ArrayList(*[]const u8).init(self.child_alloc);
    defer to_remove.deinit();

    while (iter.next()) |entry| {
        const string = entry.value_ptr.*;
        if (!string.obj.is_marked) {
            to_remove.append(entry.key_ptr) catch unreachable;
        }
    }

    while (to_remove.popOrNull()) |key| {
        self.vm.strings.removeByPtr(key);
    }
}

fn collectGarbage(self: *GC) void {
    if (comptime DEBUG_LOG_GC) {
        std.debug.print("-- gc begin\n", .{});
    }

    self.markRoots();
    self.traceReferences();
    self.removeWhiteStrings();
    self.sweep();

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
