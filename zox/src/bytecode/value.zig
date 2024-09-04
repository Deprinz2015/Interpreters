const std = @import("std");

pub const Value = union(enum) {
    number: f64,

    pub fn equals(this: Value, that: Value) bool {
        if (std.meta.activeTag(this) != std.meta.activeTag(that)) {
            return false;
        }

        return switch (this) {
            .number => this.number == that.number,
        };
    }

    pub fn format(value: Value, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .number => try writer.print("{d}", .{value.number}),
        }
    }
};
