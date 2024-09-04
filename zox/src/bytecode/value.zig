const std = @import("std");

pub const Value = union(enum) {
    number: f64,
    boolean: bool,
    nil: void,

    pub fn equals(this: Value, that: Value) bool {
        if (std.meta.activeTag(this) != std.meta.activeTag(that)) {
            return false;
        }

        return switch (this) {
            .number => this.number == that.number,
            .boolean => this.boolean == that.boolean,
            .nil => true,
        };
    }

    pub fn format(value: Value, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .number => try writer.print("{d}", .{value.number}),
            .boolean => try writer.writeAll(if (value.boolean) "true" else "false"),
            .nil => try writer.writeAll("nil"),
        }
    }
};
