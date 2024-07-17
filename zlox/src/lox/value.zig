const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Obj = struct {
    as: union(Type) {
        STRING: *String,
    },
    obj_type: Type,

    pub const Type = enum(u8) {
        STRING,
    };

    pub const String = packed struct {
        obj: *Obj,
        length: usize,
        chars: [*]const u8,
    };

    pub fn copyString(alloc: Allocator, chars: []const u8) *Obj {
        const heap_string = alloc.alloc(u8, chars.len) catch unreachable;
        @memcpy(heap_string, chars);
        return createString(alloc, heap_string.ptr, heap_string.len);
    }

    fn createString(alloc: Allocator, string: [*]const u8, length: usize) *Obj {
        const obj = createObj(alloc, .STRING);
        const obj_string = alloc.create(String) catch unreachable;
        obj_string.chars = string;
        obj_string.length = length;
        obj.as = .{ .STRING = obj_string };
        return obj;
    }

    fn createObj(alloc: Allocator, obj_type: Obj.Type) *Obj {
        const alignment = switch (obj_type) {
            .STRING => @alignOf(String),
        };
        const obj align(alignment) = alloc.create(Obj) catch unreachable;
        obj.*.obj_type = obj_type;
        return obj;
    }
};

pub const Value = union(enum) {
    BOOL: bool,
    NUMBER: f64,
    NIL: void,
    OBJ: *Obj,

    pub inline fn isObjType(value: *Value, obj_type: Obj.Type) bool {
        return value.* == .OBJ and value.OBJ.obj_type == obj_type;
    }

    pub fn format(value: Value, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .NUMBER => try writer.print("{d}", .{value.NUMBER}),
            .BOOL => try writer.writeAll(if (value.BOOL) "true" else "false"),
            .NIL => try writer.writeAll("nil"),
            .OBJ => |obj| switch (obj.obj_type) {
                .STRING => {
                    const str = obj.as.STRING;
                    try writer.print("{s}", .{str.chars[0..str.length]});
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
