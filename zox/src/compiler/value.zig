const std = @import("std");
const Allocator = std.mem.Allocator;

/// Compile time, to be used in Compiler
/// This uses static memory only
pub const Value = union(enum) {
    number: f64,
    boolean: bool,
    nil: void,
    string: []const u8,

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
                const str_l = this.string;
                const str_r = that.string;

                return std.mem.eql(u8, str_l, str_r);
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
            .string => try writer.print("{s}", .{value.string}),
        }
    }
};
