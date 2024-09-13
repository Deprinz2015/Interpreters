const std = @import("std");
const Allocator = std.mem.Allocator;
const VM = @import("Machine.zig");
const GC = @import("GC.zig");

/// Runtime, to be used in Machine.zig
/// This uses dynamically allocated memory
pub const Value = union(enum) {
    number: f64,
    boolean: bool,
    nil: void,
    string: *String,
    native: Native,
    function: Function,
    closure: *Closure,

    pub fn typeName(value: Value) []const u8 {
        return switch (value) {
            .string => "string",
            .number => "number",
            .nil => "nil",
            .boolean => "boolean",
            .native => "<native fn>",
            .function => "<fn>",
            .closure => "<closure>",
        };
    }

    pub fn equals(this: Value, that: Value) bool {
        if (std.meta.activeTag(this) != std.meta.activeTag(that)) {
            return false;
        }

        return switch (this) {
            .number => this.number == that.number,
            .boolean => this.boolean == that.boolean,
            .nil => true,
            .string => {
                const l = this.string.value;
                const r = that.string.value;
                return l.ptr == r.ptr;
            },
            .native => this.native.func == that.native.func,
            .function => this.function.start_instruction == that.function.start_instruction,
            .closure => this.closure == that.closure,
        };
    }

    pub fn isFalsey(self: Value) bool {
        if (self == .boolean) {
            return !self.boolean;
        }
        return self == .nil; // nil is false, everything else it true, so inverse for isFalsey
    }

    pub fn format(value: Value, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .number => try writer.print("{d}", .{value.number}),
            .boolean => try writer.writeAll(if (value.boolean) "true" else "false"),
            .nil => try writer.writeAll("nil"),
            .string => try writer.print("{s}", .{value.string.value}),
            .native => try writer.writeAll("<native fn>"),
            .function => try writer.writeAll("<fn>"),
            .closure => try writer.writeAll("<closure>"),
        }
    }

    pub const String = struct {
        value: []const u8,

        pub fn copyString(str: []const u8, alloc: Allocator) !Value {
            const copied = try alloc.dupe(u8, str);
            const str_obj = try alloc.create(String);
            str_obj.* = .{ .value = copied };
            return .{ .string = str_obj };
        }

        pub fn takeString(str: []const u8, alloc: Allocator) !Value {
            const str_obj = try alloc.create(String);
            str_obj.* = .{ .value = str };
            return .{ .string = str_obj };
        }
    };

    pub const Native = struct {
        func: *const Func,

        pub const Func = fn (args: []Value, vm: *VM) Value;
    };

    pub const Function = struct {
        arity: u8,
        start_instruction: usize,
    };

    pub const Closure = struct {
        arity: u8,
        upvalues: []Value,
        start_instruction: usize,

        const Error = error{NoUpvalueFound};

        pub fn upvalueAt(self: *Closure, idx: u8) Error!Value {
            if (idx >= self.upvalues.len) {
                return Error.NoUpvalueFound;
            }

            return self.upvalues[idx];
        }

        /// Sets value at the given index, returns previous value at that location
        pub fn setUpvalueAt(self: *Closure, idx: u8, new_val: Value) Error!Value {
            const old = try self.upvalueAt(idx);
            self.upvalues[idx] = new_val;
            return old;
        }

        pub fn new(alloc: Allocator, upvalues: []Value, arity: u8, start_instruction: usize) !Value {
            const obj = try alloc.create(Closure);
            obj.* = .{
                .upvalues = upvalues,
                .arity = arity,
                .start_instruction = start_instruction,
            };
            return .{ .closure = obj };
        }
    };
};
