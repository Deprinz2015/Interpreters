const std = @import("std");
const Allocator = std.mem.Allocator;

/// Runtime, to be used in Machine.zig
/// This uses dynamically allocated memory
pub const Value = union(enum) {
    number: f64,
    boolean: bool,
    nil: void,
    string: *String,

    pub fn typeName(value: Value) []const u8 {
        return switch (value) {
            .string => "string",
            .number => "number",
            .nil => "nil",
            .boolean => "boolean",
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
};
