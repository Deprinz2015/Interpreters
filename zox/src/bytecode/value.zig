const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Value = union(enum) {
    number: f64,
    boolean: bool,
    nil: void,
    string: *String,

    pub fn destroy(self: Value, alloc: Allocator) void {
        if (self == .string) {
            alloc.free(self.string.value);
            alloc.destroy(self.string);
        }
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
    };
};
