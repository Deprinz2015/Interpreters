const std = @import("std");
const Allocator = std.mem.Allocator;

const DEBUG_LOG_GC = @import("config").log_gc;

const VM = @import("VM.zig");
const Chunk = @import("Chunk.zig");

// TODO: Try with @fieldParentPointer
pub const Obj = struct {
    as: Type,
    next: ?*Obj,

    pub const Type = union(enum) {
        STRING: *String,
        FUNCTION: *Function,
        NATIVE: *NativeFunction,
        CLOSURE: *Closure,
        UPVALUE: *Upvalue,
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
        upvalue_count: u8,
        chunk: Chunk,
        name: ?*String,
    };

    pub const NativeFunction = struct {
        obj: *Obj,
        function: NativeFn,

        pub const NativeFn = *const fn (args: []Value, vm: *VM) Value;
    };

    pub const Closure = struct {
        obj: *Obj,
        function: *Function,
        upvalue_count: u8,
        upvalues: []*Upvalue,
    };

    pub const Upvalue = struct {
        obj: *Obj,
        location: *Value,
        closed: Value,
        next: ?*Upvalue,
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

    pub fn createUpvalue(alloc: Allocator, slot: *Value, vm: *VM) *Obj {
        const obj = allocObject(Upvalue, alloc, .UPVALUE, vm);
        const upvalue = obj.as.UPVALUE;
        upvalue.location = slot;
        upvalue.next = null;
        upvalue.closed = .NIL;
        return obj;
    }

    pub fn createClosure(alloc: Allocator, function: *Function, vm: *VM) *Obj {
        const upvalues = alloc.alloc(*Upvalue, function.upvalue_count) catch unreachable;
        const obj = allocObject(Closure, alloc, .CLOSURE, vm);
        const closure = obj.as.CLOSURE;
        closure.function = function;
        closure.upvalue_count = function.upvalue_count;
        closure.upvalues = upvalues;
        return obj;
    }

    pub fn createNativeFunction(alloc: Allocator, native_fn: NativeFunction.NativeFn, vm: *VM) *Obj {
        const obj = allocObject(NativeFunction, alloc, .NATIVE, vm);
        const function = obj.as.NATIVE;
        function.function = native_fn;
        return obj;
    }

    pub fn createFunction(alloc: Allocator, vm: *VM) *Obj {
        const obj = allocObject(Function, alloc, .FUNCTION, vm);
        const function = obj.as.FUNCTION;
        function.arity = 0;
        function.upvalue_count = 0;
        function.name = null;
        function.chunk = Chunk.init(alloc);
        return obj;
    }

    fn createString(alloc: Allocator, chars: [*]const u8, length: usize, vm: *VM) *Obj {
        const obj = allocObject(String, alloc, .STRING, vm);
        const string = obj.as.STRING;
        string.chars = chars;
        string.length = length;
        vm.strings.put(string.string(), string) catch unreachable;
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

    inline fn allocObject(comptime T: type, alloc: Allocator, obj_type: std.meta.Tag(Type), vm: *VM) *Obj {
        const concrete = alloc.create(T) catch unreachable;
        const obj = createObj(alloc, @unionInit(Type, @tagName(obj_type), concrete), vm);
        concrete.obj = obj;
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
        const Printer = struct {
            fn printFunction(function: *Obj.Function, inner_writer: anytype) !void {
                if (function.name) |name| {
                    try inner_writer.print("<fn {s}>", .{name.string()});
                } else {
                    try inner_writer.writeAll("<script>");
                }
            }
        };
        switch (value) {
            .NUMBER => try writer.print("{d}", .{value.NUMBER}),
            .BOOL => try writer.writeAll(if (value.BOOL) "true" else "false"),
            .NIL => try writer.writeAll("nil"),
            .OBJ => |obj| switch (obj.as) {
                .UPVALUE => try writer.writeAll("upvalue"),
                .STRING => |str| try writer.print("{s}", .{str.string()}),
                .NATIVE => try writer.writeAll("<native fn>"),
                .FUNCTION => |function| try Printer.printFunction(function, writer),
                .CLOSURE => |closure| try Printer.printFunction(closure.function, writer),
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
