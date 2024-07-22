const std = @import("std");
const Allocator = std.mem.Allocator;

const VM = @import("VM.zig");
const Chunk = @import("Chunk.zig");

// PERF: Try out data oriented design to optimize and measure
pub const Obj = struct {
    as: Type,
    next: ?*Obj,

    pub const Type = union(enum) {
        STRING: *String,
        FUNCTION: *Function,
        NATIVE: *NativeFunction,
    };

    pub const String = struct {
        obj: *Obj,
        length: usize,
        chars: [*]const u8,

        pub fn string(self: *String) []const u8 {
            return self.chars[0..self.length];
        }
    };

    pub const Function = struct {
        obj: *Obj,
        arity: u8,
        chunk: Chunk,
        name: ?*String,
    };

    pub const NativeFunction = struct {
        obj: *Obj,
        function: NativeFn,

        pub const NativeFn = *const fn (args: []Value) Value;
    };

    pub fn copyString(alloc: Allocator, chars: []const u8, vm: *VM) *Obj {
        const interned = vm.strings.get(chars);
        if (interned) |_| {
            return interned.?.obj;
        }

        const heap_string = alloc.alloc(u8, chars.len) catch unreachable;
        @memcpy(heap_string, chars);
        return createString(alloc, heap_string.ptr, heap_string.len, vm);
    }

    pub fn takeString(alloc: Allocator, chars: []const u8, vm: *VM) *Obj {
        const maybe_interned = vm.strings.get(chars);
        if (maybe_interned) |interned| {
            alloc.free(chars);
            return interned.obj;
        }

        return createString(alloc, chars.ptr, chars.len, vm);
    }

    pub fn createNativeFunction(alloc: Allocator, native_fn: NativeFunction.NativeFn, vm: *VM) *Obj {
        const function = alloc.create(NativeFunction) catch unreachable;
        function.function = native_fn;
        const obj = createObj(alloc, .{ .NATIVE = function }, vm);
        function.obj = obj;
        return obj;
    }

    pub fn createFunction(alloc: Allocator, vm: *VM) *Obj {
        const function = alloc.create(Function) catch unreachable;
        function.arity = 0;
        function.name = null;
        function.chunk = Chunk.init(alloc);
        const obj = createObj(alloc, .{ .FUNCTION = function }, vm);
        function.obj = obj;
        return obj;
    }

    fn createString(alloc: Allocator, string: [*]const u8, length: usize, vm: *VM) *Obj {
        const obj_string = alloc.create(String) catch unreachable;
        obj_string.chars = string;
        obj_string.length = length;
        const obj = createObj(alloc, .{ .STRING = obj_string }, vm);
        obj_string.obj = obj;
        vm.strings.put(obj_string.string(), obj_string) catch unreachable;
        return obj;
    }

    fn createObj(alloc: Allocator, concrete_obj: Type, vm: *VM) *Obj {
        const obj = alloc.create(Obj) catch unreachable;
        obj.as = concrete_obj;
        obj.next = null;

        if (vm.objects == null) {
            vm.objects = obj;
        } else {
            obj.next = vm.objects;
            vm.objects = obj;
        }

        return obj;
    }
};

pub const Value = union(enum) {
    BOOL: bool,
    NUMBER: f64,
    NIL: void,
    OBJ: *Obj,

    pub inline fn isObjType(value: Value, obj_type: std.meta.Tag(Obj.Type)) bool {
        return value == .OBJ and value.OBJ.as == obj_type;
    }

    pub fn format(value: Value, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .NUMBER => try writer.print("{d}", .{value.NUMBER}),
            .BOOL => try writer.writeAll(if (value.BOOL) "true" else "false"),
            .NIL => try writer.writeAll("nil"),
            .OBJ => |obj| switch (obj.as) {
                .STRING => {
                    const str = obj.as.STRING;
                    try writer.print("{s}", .{str.string()});
                },
                .FUNCTION => {
                    const function = obj.as.FUNCTION;
                    if (function.name) |name| {
                        try writer.print("<fn {s}>", .{name.string()});
                    } else {
                        try writer.writeAll("<script>");
                    }
                },
                .NATIVE => {
                    try writer.writeAll("<native fn>");
                },
            },
        }
    }
};

pub const ValueArray = struct {
    alloc: Allocator,
    capacity: usize,
    count: usize,
    values: []Value,

    pub fn init(alloc: Allocator) ValueArray {
        return .{
            .alloc = alloc,
            .values = &.{},
            .count = 0,
            .capacity = 0,
        };
    }

    pub fn write(self: *ValueArray, value: Value) void {
        if (self.capacity < self.count + 1) {
            self.growCapacity();
            self.values = self.alloc.realloc(self.values, self.capacity) catch unreachable;
        }

        self.values[self.count] = value;
        self.count += 1;
    }

    pub fn at(self: *ValueArray, offset: usize) Value {
        return self.values[offset];
    }

    /// Sets the chunk itself to undefined
    pub fn deinit(self: *ValueArray) void {
        self.alloc.free(self.values);
        self.capacity = 0;
        self.count = 0;
        self.* = undefined;
    }

    fn growCapacity(self: *ValueArray) void {
        if (self.capacity < 8) {
            self.capacity = 8;
            return;
        }
        self.capacity *= 2;
    }
};
