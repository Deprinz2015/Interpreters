const std = @import("std");
const Value = @import("../vm/value.zig").Value;

pub fn print(stack: []Value, stack_top: usize) void {
    for (stack, 0..) |value, i| {
        if (i >= stack_top) {
            break;
        }

        std.debug.print("[ {} ]", .{value});
    }
    std.debug.print("\n", .{});
}
