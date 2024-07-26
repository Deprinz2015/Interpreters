const std = @import("std");
const Allocator = std.mem.Allocator;

const DEBUG_LOG_GC = @import("config").log_gc;

const VM = @import("VM.zig");
const Chunk = @import("Chunk.zig");

pub const Obj = struct {
    type: Type,
    next: ?*Obj,
    is_marked: bool,

    pub fn as(self: *Obj, comptime T: Type) *T.getType() {
        return @fieldParentPtr("obj", self);
    }

    fn allocObj(alloc: Allocator, comptime T: Type, vm: *VM) *Obj {
        const ptr = alloc.create(T.getType()) catch unreachable;
        ptr.obj = .{
            .type = T,
            .next = vm.objects,
            .is_marked = false,
        };

        vm.objects = &ptr.obj;

        if (comptime DEBUG_LOG_GC) {
            std.debug.print("{*} allocate {} for {s}\n", .{ ptr, @sizeOf(@TypeOf(ptr.*)), @tagName(T) });
        }

        return &ptr.obj;
    }

    pub fn destroy(self: *Obj, alloc: Allocator) void {
        if (comptime DEBUG_LOG_GC) {
            std.debug.print("{*} free type {s}\n", .{ self, @tagName(self.type) });
        }
        switch (self.type) {
            .STRING => self.as(.STRING).destroy(alloc),
            .FUNCTION => self.as(.FUNCTION).destroy(alloc),
            .NATIVE => self.as(.NATIVE).destroy(alloc),
            .CLOSURE => self.as(.CLOSURE).destroy(alloc),
            .UPVALUE => self.as(.UPVALUE).destroy(alloc),
            .CLASS => self.as(.CLASS).destroy(alloc),
        }
    }

    pub const Type = enum {
        STRING,
        FUNCTION,
        NATIVE,
        CLOSURE,
        UPVALUE,
        CLASS,

        inline fn getType(self: *const Type) type {
            return switch (self.*) {
                .STRING => String,
                .FUNCTION => Function,
                .NATIVE => Native,
                .CLOSURE => Closure,
                .UPVALUE => Upvalue,
                .CLASS => Class,
            };
        }
    };

    pub const String = struct {
        obj: Obj,
        chars: []const u8,

        pub fn copy(alloc: Allocator, chars: []const u8, vm: *VM) *String {
            const maybe_interned = vm.strings.get(chars);
            if (maybe_interned) |interned| {
                return interned;
            }

            const heap_string = alloc.alloc(u8, chars.len) catch unreachable;
            @memcpy(heap_string, chars);
            return create(alloc, heap_string, vm);
        }

        pub fn take(alloc: Allocator, chars: []const u8, vm: *VM) *String {
            const maybe_interned = vm.strings.get(chars);
            if (maybe_interned) |interned| {
                alloc.free(chars);
                return interned;
            }

            return String.create(alloc, chars, vm);
        }

        fn create(alloc: Allocator, chars: []const u8, vm: *VM) *String {
            const obj = Obj.allocObj(alloc, .STRING, vm);
            const string = obj.as(.STRING);
            string.chars = chars;
            vm.push(.{ .OBJ = &string.obj });
            vm.strings.put(chars, string) catch unreachable;
            _ = vm.pop();
            return string;
        }

        fn destroy(self: *String, alloc: Allocator) void {
            alloc.free(self.chars);
            alloc.destroy(self);
        }
    };

    pub const Function = struct {
        obj: Obj,
        arity: u8,
        upvalue_count: u8,
        chunk: Chunk,
        name: ?*String,

        pub fn create(alloc: Allocator, vm: *VM) *Function {
            const obj = Obj.allocObj(alloc, .FUNCTION, vm);
            const function = obj.as(.FUNCTION);
            function.arity = 0;
            function.upvalue_count = 0;
            function.name = null;
            function.chunk = Chunk.init(alloc);
            return function;
        }

        fn destroy(self: *Function, alloc: Allocator) void {
            self.chunk.deinit();
            alloc.destroy(self);
        }
    };

    pub const Native = struct {
        obj: Obj,
        function: NativeFn,

        pub const NativeFn = *const fn (args: []Value, vm: *VM) Value;

        pub fn create(alloc: Allocator, native_fn: Native.NativeFn, vm: *VM) *Native {
            const obj = Obj.allocObj(alloc, .NATIVE, vm);
            const function = obj.as(.NATIVE);
            function.function = native_fn;
            return function;
        }

        fn destroy(self: *Native, alloc: Allocator) void {
            alloc.destroy(self);
        }
    };

    pub const Closure = struct {
        obj: Obj,
        function: *Function,
        upvalue_count: u8,
        upvalues: []?*Upvalue,

        pub fn create(alloc: Allocator, function: *Function, vm: *VM) *Closure {
            const upvalues = alloc.alloc(?*Upvalue, function.upvalue_count) catch unreachable;
            for (upvalues) |*upvalue| {
                upvalue.* = null;
            }

            const obj = Obj.allocObj(alloc, .CLOSURE, vm);
            const closure = obj.as(.CLOSURE);
            closure.function = function;
            closure.upvalue_count = function.upvalue_count;
            closure.upvalues = upvalues;
            return closure;
        }

        fn destroy(self: *Closure, alloc: Allocator) void {
            alloc.free(self.upvalues);
            alloc.destroy(self);
        }
    };

    pub const Upvalue = struct {
        obj: Obj,
        location: *Value,
        closed: Value,
        next: ?*Upvalue,

        pub fn create(alloc: Allocator, slot: *Value, vm: *VM) *Upvalue {
            const obj = Obj.allocObj(alloc, .UPVALUE, vm);
            const upvalue = obj.as(.UPVALUE);
            upvalue.location = slot;
            upvalue.next = null;
            upvalue.closed = .NIL;
            return upvalue;
        }

        fn destroy(self: *Upvalue, alloc: Allocator) void {
            alloc.destroy(self);
        }
    };

    pub const Class = struct {
        obj: Obj,
        name: *String,

        pub fn create(alloc: Allocator, name: *String, vm: *VM) *Class {
            const obj = Obj.allocObj(alloc, .CLASS, vm);
            const class = obj.as(.CLASS);
            class.name = name;
            return class;
        }

        fn destroy(self: *Class, alloc: Allocator) void {
            alloc.destroy(self);
        }
    };
};

pub const Value = union(enum) {
    BOOL: bool,
    NUMBER: f64,
    NIL: void,
    OBJ: *Obj,

    pub inline fn isObjType(value: Value, obj_type: Obj.Type) bool {
        return value == .OBJ and value.OBJ.type == obj_type;
    }

    pub fn format(value: Value, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        const Printer = struct {
            fn printFunction(function: *Obj.Function, inner_writer: anytype) !void {
                if (function.name) |name| {
                    try inner_writer.print("<fn {s}>", .{name.chars});
                } else {
                    try inner_writer.writeAll("<script>");
                }
            }
        };
        switch (value) {
            .NUMBER => try writer.print("{d}", .{value.NUMBER}),
            .BOOL => try writer.writeAll(if (value.BOOL) "true" else "false"),
            .NIL => try writer.writeAll("nil"),
            .OBJ => |obj| switch (obj.type) {
                .UPVALUE => try writer.writeAll("upvalue"),
                .STRING => try writer.print("{s}", .{obj.as(.STRING).chars}),
                .NATIVE => try writer.writeAll("<native fn>"),
                .FUNCTION => try Printer.printFunction(obj.as(.FUNCTION), writer),
                .CLOSURE => try Printer.printFunction(obj.as(.CLOSURE).function, writer),
                .CLASS => try writer.print("{s}", .{obj.as(.CLASS).name.chars}),
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
